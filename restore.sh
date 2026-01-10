#!/bin/bash
set -euo pipefail

# -------------------------
# Check input
# -------------------------
if [ $# -lt 1 ]; then
    echo "Usage: $0 <backup.dump.gz.enc> [table_name]"
    exit 1
fi

BACKUP_FILE="$1"
TABLE_NAME="${2:-}"  # optional table-specific restore

if [ ! -f "$BACKUP_FILE" ]; then
    echo "ERROR: Backup file not found: $BACKUP_FILE"
    exit 1
fi

if [ ! -f ./backup.key ]; then
    echo "ERROR: backup.key file not found in current directory"
    exit 1
fi

# -------------------------
# Load environment safely
# -------------------------
if [ -f ./.env ]; then
    set -a
    . ./.env
    set +a
else
    echo "ERROR: .env file not found"
    exit 1
fi

# -------------------------
# Restore
# -------------------------
echo "Restoring database from $BACKUP_FILE..."

DECRYPT_CMD="openssl enc -d -aes-256-cbc -pbkdf2 -pass file:./backup.key -in \"$BACKUP_FILE\" | gunzip"

PGRESTORE_CMD="docker exec -i -e PGPASSWORD=\"$POSTGRES_PASSWORD\" \"$POSTGRES_CONTAINER_NAME\" \
    pg_restore -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\" --clean --if-exists"

# Add table-specific option if provided
if [ -n "$TABLE_NAME" ]; then
    PGRESTORE_CMD="$PGRESTORE_CMD --table=$TABLE_NAME"
fi

# Execute restore
eval "$DECRYPT_CMD | $PGRESTORE_CMD"

echo "Database restored successfully from $BACKUP_FILE"
if [ -n "$TABLE_NAME" ]; then
    echo "Table restored: $TABLE_NAME"
fi
