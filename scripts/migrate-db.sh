#!/bin/bash
# Database Migration Script
# Exports data from OLD server and imports to NEW server
#
# Usage:
#   export OLD_SERVER_IP=<old-server-ip>
#   ./scripts/migrate-db.sh

set -e

# Configuration
OLD_SERVER_IP="${OLD_SERVER_IP:?ERROR: Set OLD_SERVER_IP environment variable}"
NEW_SERVER_IP="${NEW_SERVER_IP:-167.71.193.114}"
OLD_SSH_KEY="${OLD_SSH_KEY:-~/.ssh/wealthpath_key}"
NEW_SSH_KEY="${NEW_SSH_KEY:-~/.ssh/id_ed25519}"
DB_NAME="wealthpath"
DB_USER="wealthpath"
BACKUP_FILE="/tmp/wealthpath_migration_$(date +%Y%m%d_%H%M%S).sql"

echo "=========================================="
echo "WealthPath Database Migration"
echo "=========================================="
echo "OLD Server: $OLD_SERVER_IP"
echo "NEW Server: $NEW_SERVER_IP"
echo "Backup file: $BACKUP_FILE"
echo "=========================================="
echo ""

# Step 1: Export from OLD server
echo "[1/4] Exporting database from OLD server..."
ssh -i "$OLD_SSH_KEY" root@"$OLD_SERVER_IP" \
  "sudo -u postgres pg_dump -Fc --no-owner --no-acl $DB_NAME" > "$BACKUP_FILE"

BACKUP_SIZE=$(ls -lh "$BACKUP_FILE" | awk '{print $5}')
echo "      Backup created: $BACKUP_FILE ($BACKUP_SIZE)"

# Step 2: Copy to NEW server
echo "[2/4] Copying backup to NEW server..."
scp -i "$NEW_SSH_KEY" "$BACKUP_FILE" root@"$NEW_SERVER_IP":/tmp/

# Step 3: Import to NEW server
echo "[3/4] Importing database to NEW server..."
ssh -i "$NEW_SSH_KEY" root@"$NEW_SERVER_IP" << EOF
  # Drop existing data (keep schema from migrations)
  sudo -u postgres psql -d $DB_NAME -c "
    DO \\\$\\\$ DECLARE
      r RECORD;
    BEGIN
      FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename != 'flyway_schema_history') LOOP
        EXECUTE 'TRUNCATE TABLE ' || quote_ident(r.tablename) || ' CASCADE';
      END LOOP;
    END \\\$\\\$;
  "

  # Restore data
  sudo -u postgres pg_restore -d $DB_NAME --data-only --disable-triggers -v /tmp/$(basename $BACKUP_FILE) 2>&1 || true

  # Clean up
  rm /tmp/$(basename $BACKUP_FILE)
EOF

# Step 4: Verify
echo "[4/4] Verifying migration..."
echo ""
echo "Row counts on NEW server:"
ssh -i "$NEW_SSH_KEY" root@"$NEW_SERVER_IP" "sudo -u postgres psql -d $DB_NAME -c \"
  SELECT 'users' as table_name, count(*) FROM users
  UNION ALL SELECT 'transactions', count(*) FROM transactions
  UNION ALL SELECT 'budgets', count(*) FROM budgets
  UNION ALL SELECT 'savings_goals', count(*) FROM savings_goals
  UNION ALL SELECT 'recurring_transactions', count(*) FROM recurring_transactions
  UNION ALL SELECT 'debts', count(*) FROM debts
  ORDER BY table_name;
\""

# Cleanup local backup
rm "$BACKUP_FILE"

echo ""
echo "=========================================="
echo "Migration complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Restart the k8s backend to verify connection:"
echo "   KUBECONFIG=~/.kube/wealthpath-config kubectl -n wealthpath rollout restart deployment backend"
echo ""
echo "2. Test the application"
echo ""
echo "3. After verification, decommission old server"
echo "=========================================="
