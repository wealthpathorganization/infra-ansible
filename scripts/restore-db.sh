#!/bin/bash
# WealthPath Database Restore Script
# Downloads backup from DigitalOcean Spaces and restores to PostgreSQL
#
# Usage: ./restore-db.sh [backup_file_or_s3_path]
#
# Examples:
#   ./restore-db.sh                                    # List available backups
#   ./restore-db.sh /var/backups/wealthpath/daily_20251220_020000.sql.gz
#   ./restore-db.sh s3://wealthpath-backups/daily/daily_20251220_020000.sql.gz
#   ./restore-db.sh latest                             # Restore latest daily backup
#
# Environment variables:
#   DO_SPACES_KEY      - DigitalOcean Spaces access key
#   DO_SPACES_SECRET   - DigitalOcean Spaces secret key
#   DO_SPACES_BUCKET   - Bucket name
#   DO_SPACES_REGION   - Region (e.g., nyc3)
#   POSTGRES_USER      - Database user (default: wealthpath)
#   POSTGRES_DB        - Database name (default: wealthpath)

set -euo pipefail

# Configuration
POSTGRES_USER="${POSTGRES_USER:-wealthpath}"
POSTGRES_DB="${POSTGRES_DB:-wealthpath}"
BACKUP_DIR="/var/backups/wealthpath"
RESTORE_FILE=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# Function to list available backups
list_backups() {
    echo ""
    log_info "Available local backups:"
    echo "─────────────────────────────────────────────────────────"
    if [[ -d "${BACKUP_DIR}" ]]; then
        ls -lh "${BACKUP_DIR}"/*.sql.gz 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}' || echo "  No local backups found"
    else
        echo "  No local backups found"
    fi
    
    if [[ -n "${DO_SPACES_KEY:-}" && -n "${DO_SPACES_SECRET:-}" && -n "${DO_SPACES_BUCKET:-}" ]]; then
        SPACES_ENDPOINT="${DO_SPACES_REGION:-nyc3}.digitaloceanspaces.com"
        
        echo ""
        log_info "Available remote backups (DigitalOcean Spaces):"
        echo "─────────────────────────────────────────────────────────"
        
        for type in daily hourly weekly; do
            echo "  ${type}:"
            s3cmd ls "s3://${DO_SPACES_BUCKET}/${type}/" \
                --host="${SPACES_ENDPOINT}" \
                --host-bucket="%(bucket)s.${SPACES_ENDPOINT}" \
                --access_key="${DO_SPACES_KEY}" \
                --secret_key="${DO_SPACES_SECRET}" 2>/dev/null | tail -5 | awk '{print "    " $NF " (" $3 ")"}' || echo "    None"
        done
    fi
    echo ""
}

# Function to download from Spaces
download_from_spaces() {
    local s3_path="$1"
    local local_file="${BACKUP_DIR}/$(basename ${s3_path})"
    
    SPACES_ENDPOINT="${DO_SPACES_REGION:-nyc3}.digitaloceanspaces.com"
    
    log_info "Downloading from ${s3_path}..."
    s3cmd get "${s3_path}" "${local_file}" \
        --host="${SPACES_ENDPOINT}" \
        --host-bucket="%(bucket)s.${SPACES_ENDPOINT}" \
        --access_key="${DO_SPACES_KEY}" \
        --secret_key="${DO_SPACES_SECRET}" \
        --force \
        --quiet
    
    echo "${local_file}"
}

# Function to get latest backup
get_latest_backup() {
    local type="${1:-daily}"
    
    if [[ -n "${DO_SPACES_KEY:-}" && -n "${DO_SPACES_SECRET:-}" && -n "${DO_SPACES_BUCKET:-}" ]]; then
        SPACES_ENDPOINT="${DO_SPACES_REGION:-nyc3}.digitaloceanspaces.com"
        
        LATEST=$(s3cmd ls "s3://${DO_SPACES_BUCKET}/${type}/" \
            --host="${SPACES_ENDPOINT}" \
            --host-bucket="%(bucket)s.${SPACES_ENDPOINT}" \
            --access_key="${DO_SPACES_KEY}" \
            --secret_key="${DO_SPACES_SECRET}" 2>/dev/null | tail -1 | awk '{print $NF}')
        
        if [[ -n "${LATEST}" ]]; then
            echo "${LATEST}"
            return
        fi
    fi
    
    # Fallback to local
    ls -t "${BACKUP_DIR}"/${type}_*.sql.gz 2>/dev/null | head -1
}

# Main logic
if [[ $# -eq 0 ]]; then
    list_backups
    echo "Usage: $0 <backup_file_or_s3_path>"
    echo "       $0 latest                    # Restore latest daily backup"
    echo "       $0 latest:hourly             # Restore latest hourly backup"
    exit 0
fi

INPUT="$1"

# Handle "latest" keyword
if [[ "${INPUT}" == "latest" ]]; then
    RESTORE_FILE=$(get_latest_backup "daily")
elif [[ "${INPUT}" == latest:* ]]; then
    TYPE="${INPUT#latest:}"
    RESTORE_FILE=$(get_latest_backup "${TYPE}")
elif [[ "${INPUT}" == s3://* ]]; then
    RESTORE_FILE=$(download_from_spaces "${INPUT}")
else
    RESTORE_FILE="${INPUT}"
fi

if [[ -z "${RESTORE_FILE}" || ! -f "${RESTORE_FILE}" ]]; then
    log_error "Backup file not found: ${RESTORE_FILE:-<empty>}"
    exit 1
fi

log_info "=============================="
log_info "WealthPath Database Restore"
log_info "=============================="
log_info "Backup file: ${RESTORE_FILE}"
log_info "Database: ${POSTGRES_DB}"
log_info "User: ${POSTGRES_USER}"
echo ""

# Confirm restore
read -p "⚠️  This will OVERWRITE the current database. Continue? (yes/no): " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
    log_warn "Restore cancelled"
    exit 0
fi

# Stop dependent services
log_step "Stopping dependent services..."
cd /opt/wealthpath 2>/dev/null || true
if [[ -f "docker-compose.deploy.yaml" ]]; then
    docker compose -f docker-compose.deploy.yaml stop backend admin 2>/dev/null || true
    log_info "Stopped backend and admin services"
fi

# Verify backup integrity
log_step "Verifying backup integrity..."
if ! gunzip -t "${RESTORE_FILE}" 2>/dev/null; then
    log_error "Backup file is corrupted"
    exit 1
fi
log_info "Backup integrity verified"

# Restore the database
log_step "Restoring database..."
gunzip -c "${RESTORE_FILE}" | sudo -u postgres psql -d "${POSTGRES_DB}" -q

log_info "Database restored successfully"

# Restart services
log_step "Restarting services..."
if [[ -f "docker-compose.deploy.yaml" ]]; then
    docker compose -f docker-compose.deploy.yaml start backend admin 2>/dev/null || true
    log_info "Restarted backend and admin services"
fi

# Verify
log_step "Verifying database..."
TABLES=$(sudo -u postgres psql -d "${POSTGRES_DB}" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'")
log_info "Database has ${TABLES} tables"

log_info "=============================="
log_info "Restore complete!"
log_info "=============================="

exit 0

