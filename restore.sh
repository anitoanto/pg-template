#!/bin/sh

# Exit on error
set -e

# Check for input file argument
if [ -z "$1" ]; then
    echo "Usage: $0 <backup.sql.gz.enc>"
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Ensure encryption key exists
if [ ! -f backup.key ]; then
    echo "backup.key file not found in current directory"
    exit 1
fi

# Load environment variables from .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo ".env file not found"
    exit 1
fi

# Decrypt and restore backup
openssl enc -d -aes-256-cbc -pbkdf2 \
    -pass file:backup.key \
    -in "${BACKUP_FILE}" \
| gunzip \
| docker exec -e \
    PGPASSWORD="${POSTGRES_PASSWORD}" \
    -i "${POSTGRES_CONTAINER_NAME}" \
    psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"

echo "Database restored from ${BACKUP_FILE}"
