#!/bin/bash
# WealthPath Database Backup Script
# Creates PostgreSQL backup and uploads to DigitalOcean Spaces
#
# Usage: ./backup-db.sh [backup_type]
#   backup_type: hourly, daily, weekly (default: daily)
#
# Environment variables:
#   DO_SPACES_KEY      - DigitalOcean Spaces access key
#   DO_SPACES_SECRET   - DigitalOcean Spaces secret key
#   DO_SPACES_BUCKET   - Bucket name (e.g., wealthpath-backups)
#   DO_SPACES_REGION   - Region (e.g., nyc3)
#   POSTGRES_USER      - Database user (default: wealthpath)
#   POSTGRES_DB        - Database name (default: wealthpath)

set -euo pipefail

# Configuration
BACKUP_TYPE="${1:-daily}"
POSTGRES_USER="${POSTGRES_USER:-wealthpath}"
POSTGRES_DB="${POSTGRES_DB:-wealthpath}"
BACKUP_DIR="/var/backups/wealthpath"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_TYPE}_${TIMESTAMP}.sql.gz"

# Retention periods (in days)
declare -A RETENTION=(
    ["hourly"]=1
    ["daily"]=7
    ["weekly"]=30
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Validate backup type
if [[ ! "${BACKUP_TYPE}" =~ ^(hourly|daily|weekly)$ ]]; then
    log_error "Invalid backup type: ${BACKUP_TYPE}"
    log_error "Usage: $0 [hourly|daily|weekly]"
    exit 1
fi

log_info "Starting ${BACKUP_TYPE} backup..."
log_info "Database: ${POSTGRES_DB}, User: ${POSTGRES_USER}"

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Create the backup
log_info "Creating PostgreSQL dump..."
sudo -u postgres pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" --clean --if-exists | gzip > "${BACKUP_FILE}"

# Verify backup
if [[ ! -s "${BACKUP_FILE}" ]]; then
    log_error "Backup failed - file is empty"
    rm -f "${BACKUP_FILE}"
    exit 1
fi

BACKUP_SIZE=$(ls -lh "${BACKUP_FILE}" | awk '{print $5}')
log_info "Backup created: ${BACKUP_FILE} (${BACKUP_SIZE})"

# Verify backup integrity
log_info "Verifying backup integrity..."
if ! gunzip -t "${BACKUP_FILE}" 2>/dev/null; then
    log_error "Backup verification failed - file is corrupted"
    exit 1
fi
log_info "Backup integrity verified"

# Upload to DigitalOcean Spaces (if configured)
if [[ -n "${DO_SPACES_KEY:-}" && -n "${DO_SPACES_SECRET:-}" && -n "${DO_SPACES_BUCKET:-}" ]]; then
    log_info "Uploading to DigitalOcean Spaces..."
    
    SPACES_ENDPOINT="${DO_SPACES_REGION:-nyc3}.digitaloceanspaces.com"
    SPACES_PATH="${BACKUP_TYPE}/$(basename ${BACKUP_FILE})"
    
    # Use s3cmd for upload
    if command -v s3cmd &> /dev/null; then
        s3cmd put "${BACKUP_FILE}" "s3://${DO_SPACES_BUCKET}/${SPACES_PATH}" \
            --host="${SPACES_ENDPOINT}" \
            --host-bucket="%(bucket)s.${SPACES_ENDPOINT}" \
            --access_key="${DO_SPACES_KEY}" \
            --secret_key="${DO_SPACES_SECRET}" \
            --no-mime-magic \
            --quiet
        log_info "Uploaded to s3://${DO_SPACES_BUCKET}/${SPACES_PATH}"
    else
        log_warn "s3cmd not installed - skipping upload"
    fi
else
    log_warn "DO Spaces not configured - backup stored locally only"
fi

# Cleanup old local backups
RETENTION_DAYS="${RETENTION[${BACKUP_TYPE}]}"
log_info "Cleaning up ${BACKUP_TYPE} backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -name "${BACKUP_TYPE}_*.sql.gz" -mtime +${RETENTION_DAYS} -delete

# Cleanup old remote backups (if configured)
if [[ -n "${DO_SPACES_KEY:-}" && -n "${DO_SPACES_SECRET:-}" && -n "${DO_SPACES_BUCKET:-}" ]]; then
    if command -v s3cmd &> /dev/null; then
        log_info "Cleaning up old remote backups..."
        CUTOFF_DATE=$(date -d "-${RETENTION_DAYS} days" +%Y%m%d 2>/dev/null || date -v-${RETENTION_DAYS}d +%Y%m%d)
        
        s3cmd ls "s3://${DO_SPACES_BUCKET}/${BACKUP_TYPE}/" \
            --host="${SPACES_ENDPOINT}" \
            --host-bucket="%(bucket)s.${SPACES_ENDPOINT}" \
            --access_key="${DO_SPACES_KEY}" \
            --secret_key="${DO_SPACES_SECRET}" 2>/dev/null | while read -r line; do
            
            FILE_DATE=$(echo "$line" | grep -oE '[0-9]{8}' | head -1)
            FILE_PATH=$(echo "$line" | awk '{print $NF}')
            
            if [[ -n "${FILE_DATE}" && "${FILE_DATE}" < "${CUTOFF_DATE}" ]]; then
                s3cmd del "${FILE_PATH}" \
                    --host="${SPACES_ENDPOINT}" \
                    --host-bucket="%(bucket)s.${SPACES_ENDPOINT}" \
                    --access_key="${DO_SPACES_KEY}" \
                    --secret_key="${DO_SPACES_SECRET}" \
                    --quiet 2>/dev/null || true
                log_info "Deleted old backup: ${FILE_PATH}"
            fi
        done
    fi
fi

# Summary
log_info "=============================="
log_info "Backup complete!"
log_info "  Type: ${BACKUP_TYPE}"
log_info "  File: ${BACKUP_FILE}"
log_info "  Size: ${BACKUP_SIZE}"
log_info "=============================="

exit 0
