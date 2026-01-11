#!/bin/bash
# WealthPath Database Migration Script - Old Server to New K8s DB
# Migrates PostgreSQL data from the original single-server to the new dedicated DB droplet
#
# Usage: ./migrate-to-k8s-db.sh
#
# Prerequisites:
#   - SSH access to both old and new servers
#   - OLD_SERVER_IP environment variable set (or will prompt)
#   - NEW_DB_SERVER_IP environment variable set (default: 167.71.193.114)
#   - POSTGRES_PASSWORD environment variable for the new DB
#
# What this script does:
#   1. Creates a backup on the OLD server
#   2. Downloads the backup locally
#   3. Uploads the backup to the NEW DB server
#   4. Restores the backup on the NEW DB server
#   5. Verifies the migration

set -euo pipefail

# Configuration
OLD_SERVER_IP="${OLD_SERVER_IP:-}"
NEW_DB_SERVER_IP="${NEW_DB_SERVER_IP:-167.71.193.114}"
POSTGRES_USER="${POSTGRES_USER:-wealthpath}"
POSTGRES_DB="${POSTGRES_DB:-wealthpath}"
SSH_KEY_OLD="${SSH_KEY_OLD:-~/.ssh/wealthpath_key}"
SSH_KEY_NEW="${SSH_KEY_NEW:-~/.ssh/id_ed25519}"
BACKUP_DIR="/tmp/wealthpath_migration"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="migration_${TIMESTAMP}.sql.gz"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# Prompt for missing variables
if [[ -z "${OLD_SERVER_IP}" ]]; then
    echo -n "Enter OLD server IP address: "
    read OLD_SERVER_IP
    if [[ -z "${OLD_SERVER_IP}" ]]; then
        log_error "OLD_SERVER_IP is required"
        exit 1
    fi
fi

echo ""
log_info "======================================"
log_info "WealthPath Database Migration"
log_info "======================================"
log_info "OLD Server: ${OLD_SERVER_IP}"
log_info "NEW DB Server: ${NEW_DB_SERVER_IP}"
log_info "Database: ${POSTGRES_DB}"
log_info "User: ${POSTGRES_USER}"
echo ""

# Confirm migration
log_warn "This will migrate the database from OLD server to NEW server."
log_warn "The OLD database will NOT be modified (read-only operation)."
log_warn "The NEW database will be OVERWRITTEN with data from OLD."
echo ""
read -p "Continue with migration? (yes/no): " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
    log_warn "Migration cancelled"
    exit 0
fi

# Create local backup directory
mkdir -p "${BACKUP_DIR}"

# =============================================================================
# STEP 1: Create backup on OLD server
# =============================================================================
log_step "Step 1/5: Creating backup on OLD server (${OLD_SERVER_IP})..."

ssh -i "${SSH_KEY_OLD}" -o StrictHostKeyChecking=no root@"${OLD_SERVER_IP}" << 'REMOTE_BACKUP'
set -e
BACKUP_FILE="/tmp/wealthpath_migration_export.sql.gz"
POSTGRES_USER="wealthpath"
POSTGRES_DB="wealthpath"

echo "Creating PostgreSQL backup..."
sudo -u postgres pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" --clean --if-exists | gzip > "${BACKUP_FILE}"

# Verify backup
if [[ ! -s "${BACKUP_FILE}" ]]; then
    echo "ERROR: Backup file is empty"
    exit 1
fi

# Show backup size
ls -lh "${BACKUP_FILE}"

# Verify integrity
if ! gunzip -t "${BACKUP_FILE}" 2>/dev/null; then
    echo "ERROR: Backup integrity check failed"
    exit 1
fi

echo "Backup created successfully: ${BACKUP_FILE}"
REMOTE_BACKUP

if [[ $? -ne 0 ]]; then
    log_error "Failed to create backup on OLD server"
    exit 1
fi
log_info "Backup created on OLD server"

# =============================================================================
# STEP 2: Download backup locally
# =============================================================================
log_step "Step 2/5: Downloading backup to local machine..."

scp -i "${SSH_KEY_OLD}" -o StrictHostKeyChecking=no \
    root@"${OLD_SERVER_IP}":/tmp/wealthpath_migration_export.sql.gz \
    "${BACKUP_DIR}/${BACKUP_FILE}"

if [[ ! -s "${BACKUP_DIR}/${BACKUP_FILE}" ]]; then
    log_error "Downloaded backup file is empty or missing"
    exit 1
fi

BACKUP_SIZE=$(ls -lh "${BACKUP_DIR}/${BACKUP_FILE}" | awk '{print $5}')
log_info "Downloaded backup: ${BACKUP_DIR}/${BACKUP_FILE} (${BACKUP_SIZE})"

# =============================================================================
# STEP 3: Upload backup to NEW DB server
# =============================================================================
log_step "Step 3/5: Uploading backup to NEW DB server (${NEW_DB_SERVER_IP})..."

scp -i "${SSH_KEY_NEW}" -o StrictHostKeyChecking=no \
    "${BACKUP_DIR}/${BACKUP_FILE}" \
    root@"${NEW_DB_SERVER_IP}":/tmp/wealthpath_migration_import.sql.gz

log_info "Backup uploaded to NEW DB server"

# =============================================================================
# STEP 4: Restore backup on NEW DB server
# =============================================================================
log_step "Step 4/5: Restoring backup on NEW DB server..."

ssh -i "${SSH_KEY_NEW}" -o StrictHostKeyChecking=no root@"${NEW_DB_SERVER_IP}" << 'REMOTE_RESTORE'
set -e
BACKUP_FILE="/tmp/wealthpath_migration_import.sql.gz"
POSTGRES_DB="wealthpath"

echo "Verifying backup integrity..."
if ! gunzip -t "${BACKUP_FILE}" 2>/dev/null; then
    echo "ERROR: Backup file is corrupted"
    exit 1
fi

echo "Restoring database..."
gunzip -c "${BACKUP_FILE}" | sudo -u postgres psql -d "${POSTGRES_DB}" -q

echo "Database restored successfully"

# Cleanup
rm -f "${BACKUP_FILE}"
REMOTE_RESTORE

if [[ $? -ne 0 ]]; then
    log_error "Failed to restore backup on NEW DB server"
    exit 1
fi
log_info "Database restored on NEW DB server"

# =============================================================================
# STEP 5: Verify migration
# =============================================================================
log_step "Step 5/5: Verifying migration..."

# Get table count from OLD server
OLD_TABLE_COUNT=$(ssh -i "${SSH_KEY_OLD}" -o StrictHostKeyChecking=no root@"${OLD_SERVER_IP}" \
    "sudo -u postgres psql -d ${POSTGRES_DB} -t -c \"SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'\"" | tr -d ' ')

# Get table count from NEW server
NEW_TABLE_COUNT=$(ssh -i "${SSH_KEY_NEW}" -o StrictHostKeyChecking=no root@"${NEW_DB_SERVER_IP}" \
    "sudo -u postgres psql -d ${POSTGRES_DB} -t -c \"SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'\"" | tr -d ' ')

log_info "OLD server tables: ${OLD_TABLE_COUNT}"
log_info "NEW server tables: ${NEW_TABLE_COUNT}"

if [[ "${OLD_TABLE_COUNT}" -eq "${NEW_TABLE_COUNT}" ]]; then
    log_info "Table count matches - migration successful!"
else
    log_warn "Table count mismatch - please verify manually"
fi

# Get sample row counts from key tables
echo ""
log_info "Sample row counts on NEW server:"
ssh -i "${SSH_KEY_NEW}" -o StrictHostKeyChecking=no root@"${NEW_DB_SERVER_IP}" << 'VERIFY'
sudo -u postgres psql -d wealthpath -c "
SELECT
    schemaname,
    relname as table_name,
    n_live_tup as row_count
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC
LIMIT 10;
"
VERIFY

# Cleanup local backup
rm -rf "${BACKUP_DIR}"

# Cleanup OLD server temp file
ssh -i "${SSH_KEY_OLD}" -o StrictHostKeyChecking=no root@"${OLD_SERVER_IP}" \
    "rm -f /tmp/wealthpath_migration_export.sql.gz" || true

echo ""
log_info "======================================"
log_info "Migration Complete!"
log_info "======================================"
log_info ""
log_info "Next steps:"
log_info "  1. Update k8s secrets to point to new database"
log_info "  2. Verify application connectivity"
log_info "  3. Monitor for any issues"
log_info "  4. Once verified, decommission old server"
log_info ""
log_info "Old server (${OLD_SERVER_IP}) is still running."
log_info "Run 'decommission-old-server.sh' when ready to shut it down."

exit 0
