#!/bin/bash
set -euo pipefail

# -------------------------
# Config and arguments
# -------------------------
BACKUP_DIR="$1"

if [ -z "$BACKUP_DIR" ]; then
  echo "Usage: $0 <backup_dir>"
  exit 1
fi

# -------------------------
# Check required files
# -------------------------
if [ ! -f ./backup.key ]; then
  echo "ERROR: backup.key missing"
  exit 1
fi

if [ ! -f ./.env ]; then
  echo "ERROR: .env missing"
  exit 1
fi

# -------------------------
# Load environment safely
# -------------------------
set -a
. ./.env
set +a

# Default retention if not set
KEEP_LOCAL=${KEEP_LOCAL:-5}
KEEP_REMOTE=${KEEP_REMOTE:-10}

# -------------------------
# Prepare filenames
# -------------------------
TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
FILENAME="${POSTGRES_DB}_${TIMESTAMP}.dump.gz.enc"
LOCAL_FILE="${BACKUP_DIR}/${FILENAME}"

mkdir -p "$BACKUP_DIR"

# -------------------------
# Backup
# -------------------------
echo "Creating backup: $LOCAL_FILE ..."

docker exec \
  -e PGPASSWORD="$POSTGRES_PASSWORD" \
  "$POSTGRES_CONTAINER_NAME" \
  pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB" \
| gzip \
| openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:./backup.key \
> "$LOCAL_FILE"

echo "Backup created successfully."

# -------------------------
# Upload to R2 / S3
# -------------------------
echo "Uploading to R2: ${R2_BUCKET}/${POSTGRES_CONTAINER_NAME}/${FILENAME} ..."

aws s3 cp \
  "$LOCAL_FILE" \
  "s3://${R2_BUCKET}/${POSTGRES_CONTAINER_NAME}/${FILENAME}" \
  --endpoint-url "$R2_ENDPOINT"

echo "Upload complete."

# -------------------------
# Cleanup local backups
# -------------------------
echo "Cleaning up local backups (keeping $KEEP_LOCAL newest)..."

ls -1t "$BACKUP_DIR"/*.enc 2>/dev/null | tail -n +$((KEEP_LOCAL + 1)) | xargs -r -I {} rm -- {}

# -------------------------
# Cleanup remote backups
# -------------------------
echo "Cleaning up remote backups (keeping $KEEP_REMOTE newest)..."

# List remote files sorted by last modified descending
aws s3api list-objects --bucket "$R2_BUCKET" --prefix "${POSTGRES_CONTAINER_NAME}/" --endpoint-url "$R2_ENDPOINT" \
  --query "Contents | sort_by(@,&LastModified) | reverse(@)[${KEEP_REMOTE}:].Key" --output text \
| while read -r key; do
    echo "Deleting remote backup: $key"
    aws s3 rm "s3://${R2_BUCKET}/${key}" --endpoint-url "$R2_ENDPOINT"
  done

echo "Backup process completed successfully: $FILENAME"
