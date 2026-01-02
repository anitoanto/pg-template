#!/bin/sh

# Exit on error
set -e

# Check BACKUP_DIR argument
if [ -z "$1" ]; then
    echo "Usage: $0 <backup_dir>"
    exit 1
fi

BACKUP_DIR="$1"

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

TIMESTAMP=$(date -u +%Y%m%d_%H%M%S%N)
OUTPUT_FILE="${BACKUP_DIR}/${POSTGRES_CONTAINER_NAME}_${POSTGRES_DB}_${TIMESTAMP}.sql.gz.enc"

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

docker exec -e \
    PGPASSWORD="${POSTGRES_PASSWORD}" \
    -t "${POSTGRES_CONTAINER_NAME}" \
    pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" \
| gzip \
| openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:backup.key \
> "${OUTPUT_FILE}"

echo "Encrypted backup saved to ${OUTPUT_FILE}"
