#!/bin/bash
# WealthPath Old Server Decommissioning Script
# Safely shuts down services on the old single-server deployment
#
# Usage: ./decommission-old-server.sh
#
# Prerequisites:
#   - Migration completed successfully (run migrate-to-k8s-db.sh first)
#   - OLD_SERVER_IP environment variable set (or will prompt)
#   - SSH access to the old server
#
# What this script does:
#   1. Creates a final backup (safety measure)
#   2. Stops Docker containers
#   3. Stops PostgreSQL service
#   4. Optionally removes all data
#   5. Provides instructions for droplet deletion

set -euo pipefail

# Configuration
OLD_SERVER_IP="${OLD_SERVER_IP:-}"
SSH_KEY="${SSH_KEY:-~/.ssh/wealthpath_key}"
BACKUP_DIR="/tmp/wealthpath_final_backup"

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
    echo -n "Enter OLD server IP address to decommission: "
    read OLD_SERVER_IP
    if [[ -z "${OLD_SERVER_IP}" ]]; then
        log_error "OLD_SERVER_IP is required"
        exit 1
    fi
fi

echo ""
log_info "======================================"
log_info "WealthPath Old Server Decommissioning"
log_info "======================================"
log_info "Server: ${OLD_SERVER_IP}"
echo ""

# Multiple confirmations for safety
log_warn "WARNING: This will shut down all services on ${OLD_SERVER_IP}"
log_warn ""
log_warn "Before proceeding, ensure:"
log_warn "  1. Database migration to new server is complete"
log_warn "  2. New k8s deployment is working correctly"
log_warn "  3. DNS has been updated (if applicable)"
log_warn "  4. All users/traffic is going to the new system"
echo ""
read -p "Have you completed the migration and verified the new system? (yes/no): " CONFIRM1
if [[ "${CONFIRM1}" != "yes" ]]; then
    log_warn "Decommissioning cancelled - please complete migration first"
    exit 0
fi

read -p "Are you SURE you want to decommission ${OLD_SERVER_IP}? (yes/no): " CONFIRM2
if [[ "${CONFIRM2}" != "yes" ]]; then
    log_warn "Decommissioning cancelled"
    exit 0
fi

# Create local backup directory
mkdir -p "${BACKUP_DIR}"

# =============================================================================
# STEP 1: Final backup (safety measure)
# =============================================================================
log_step "Step 1/4: Creating final safety backup..."

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FINAL_BACKUP="final_backup_${TIMESTAMP}.sql.gz"

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no root@"${OLD_SERVER_IP}" << REMOTE_BACKUP
set -e
BACKUP_FILE="/tmp/${FINAL_BACKUP}"

echo "Creating final PostgreSQL backup..."
if systemctl is-active --quiet postgresql; then
    sudo -u postgres pg_dump -U wealthpath -d wealthpath --clean --if-exists | gzip > "\${BACKUP_FILE}" || true
    ls -lh "\${BACKUP_FILE}" 2>/dev/null || echo "No backup created (database may be empty)"
else
    echo "PostgreSQL not running - skipping backup"
fi
REMOTE_BACKUP

# Download final backup if it exists
scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    root@"${OLD_SERVER_IP}":/tmp/${FINAL_BACKUP} \
    "${BACKUP_DIR}/${FINAL_BACKUP}" 2>/dev/null || true

if [[ -f "${BACKUP_DIR}/${FINAL_BACKUP}" ]]; then
    log_info "Final backup saved to: ${BACKUP_DIR}/${FINAL_BACKUP}"
else
    log_warn "No final backup downloaded (may not exist)"
fi

# =============================================================================
# STEP 2: Stop Docker containers
# =============================================================================
log_step "Step 2/4: Stopping Docker containers..."

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no root@"${OLD_SERVER_IP}" << 'STOP_DOCKER'
set -e
cd /opt/wealthpath 2>/dev/null || true

echo "Stopping Docker Compose services..."
if [[ -f "docker-compose.deploy.yaml" ]]; then
    docker compose -f docker-compose.deploy.yaml down || true
elif [[ -f "docker-compose.yml" ]]; then
    docker compose down || true
fi

echo "Stopping all remaining containers..."
docker stop $(docker ps -q) 2>/dev/null || true

echo "Docker containers stopped"
docker ps
STOP_DOCKER

log_info "Docker containers stopped"

# =============================================================================
# STEP 3: Stop PostgreSQL
# =============================================================================
log_step "Step 3/4: Stopping PostgreSQL service..."

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no root@"${OLD_SERVER_IP}" << 'STOP_POSTGRES'
set -e
echo "Stopping PostgreSQL..."
systemctl stop postgresql || true
systemctl disable postgresql || true
echo "PostgreSQL stopped and disabled"
STOP_POSTGRES

log_info "PostgreSQL stopped"

# =============================================================================
# STEP 4: Optional data cleanup
# =============================================================================
log_step "Step 4/4: Data cleanup options..."

echo ""
log_warn "The services are now stopped."
log_info "You have the following options:"
echo ""
echo "  1. KEEP - Leave data on server (recommended until fully verified)"
echo "  2. REMOVE - Delete application data and Docker volumes"
echo "  3. DESTROY - Delete droplet via DigitalOcean console"
echo ""
read -p "Choose an option (1/2/3): " CLEANUP_OPTION

case "${CLEANUP_OPTION}" in
    2)
        log_warn "Removing application data and Docker volumes..."
        read -p "This is IRREVERSIBLE. Type 'DELETE' to confirm: " DELETE_CONFIRM
        if [[ "${DELETE_CONFIRM}" == "DELETE" ]]; then
            ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no root@"${OLD_SERVER_IP}" << 'CLEANUP'
set -e
echo "Removing Docker volumes..."
docker volume prune -f || true

echo "Removing application directory..."
rm -rf /opt/wealthpath

echo "Removing PostgreSQL data..."
rm -rf /var/lib/postgresql

echo "Removing backup files..."
rm -rf /var/backups/wealthpath

echo "Cleanup complete"
CLEANUP
            log_info "Data removed from server"
        else
            log_info "Cleanup cancelled - data preserved"
        fi
        ;;
    3)
        echo ""
        log_info "To delete the droplet:"
        log_info "  1. Go to DigitalOcean Console: https://cloud.digitalocean.com/droplets"
        log_info "  2. Find the droplet with IP: ${OLD_SERVER_IP}"
        log_info "  3. Click '...' menu -> 'Destroy'"
        log_info "  4. Confirm deletion"
        echo ""
        log_warn "Make sure you have verified the final backup before deleting!"
        ;;
    *)
        log_info "Keeping data on server"
        log_info "Services are stopped but data remains intact"
        ;;
esac

echo ""
log_info "======================================"
log_info "Decommissioning Complete!"
log_info "======================================"
log_info ""
log_info "Status:"
log_info "  - Docker containers: STOPPED"
log_info "  - PostgreSQL: STOPPED and DISABLED"
if [[ -f "${BACKUP_DIR}/${FINAL_BACKUP}" ]]; then
    log_info "  - Final backup: ${BACKUP_DIR}/${FINAL_BACKUP}"
fi
log_info ""
log_info "The server ${OLD_SERVER_IP} is now idle."
log_info "It will continue to incur costs until deleted from DigitalOcean."
log_info ""
log_info "Recommended: Keep the server running for 24-48 hours after"
log_info "migration, then delete once you're confident in the new system."

exit 0
