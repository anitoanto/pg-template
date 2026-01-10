#!/bin/sh
set -e

BACKUP_DIR="$1"

if [ -z "$BACKUP_DIR" ]; then
  echo "Usage: $0 <backup_dir>"
  exit 1
fi

if [ ! -f ./backup.key ]; then
  echo "backup.key missing"
  exit 1
fi

if [ ! -f ./.env ]; then
  echo ".env missing"
  exit 1
fi

export $(grep -v '^#' ./.env | xargs)

TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
FILENAME="${POSTGRES_DB}_${TIMESTAMP}.sql.gz.enc"
LOCAL_FILE="${BACKUP_DIR}/${FILENAME}"

mkdir -p "$BACKUP_DIR"

echo "Creating backup..."

docker exec \
  -e PGPASSWORD="$POSTGRES_PASSWORD" \
  "$POSTGRES_CONTAINER_NAME" \
  pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" \
| gzip \
| openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:./backup.key \
> "$LOCAL_FILE"

echo "Uploading to R2..."

aws s3 cp \
  "$LOCAL_FILE" \
  "s3://${R2_BUCKET}/${POSTGRES_CONTAINER_NAME}/${FILENAME}" \
  --endpoint-url "$R2_ENDPOINT"

echo "Cleaning local backups..."
ls -1t "$BACKUP_DIR"/*.enc | tail -n +$(($KEEP_LOCAL+1)) | xargs -r rm --

echo "Cleaning remote backups..."
aws s3 ls "s3://${R2_BUCKET}/${POSTGRES_CONTAINER_NAME}/" \
  --endpoint-url "$R2_ENDPOINT" \
| awk '{print $4}' \
| sort -r \
| tail -n +$(($KEEP_REMOTE+1)) \
| while read f; do
    aws s3 rm \
      "s3://${R2_BUCKET}/${POSTGRES_CONTAINER_NAME}/$f" \
      --endpoint-url "$R2_ENDPOINT"
  done

echo "Backup completed: $FILENAME"
