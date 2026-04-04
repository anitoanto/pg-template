#!/bin/bash
set -euo pipefail

BACKUP_DIR="${1:-}"

if [ -z "$BACKUP_DIR" ]; then
  echo "Usage: $0 <backup_dir>"
  exit 1
fi

for required_file in ./backup.key ./.env; do
  if [ ! -f "$required_file" ]; then
    echo "ERROR: ${required_file} not found"
    exit 1
  fi
done

set -a
. ./.env
set +a

KEEP_LOCAL=${KEEP_LOCAL:-5}
KEEP_REMOTE=${KEEP_REMOTE:-10}
TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
FILENAME="${POSTGRES_DB}_${TIMESTAMP}.dump.gz.enc"
LOCAL_FILE="${BACKUP_DIR}/${FILENAME}"

mkdir -p "$BACKUP_DIR"

echo "[${POSTGRES_CONTAINER_NAME}] Creating backup: ${FILENAME}"

export PGPASSWORD="$POSTGRES_PASSWORD"
pg_dump -h "$POSTGRES_CONTAINER_NAME" -U "$POSTGRES_USER" -Fc "$POSTGRES_DB" \
  | gzip \
  | openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:./backup.key \
  > "$LOCAL_FILE"
unset PGPASSWORD

REMOTE_PATH="s3://${R2_BUCKET}/${POSTGRES_CONTAINER_NAME}/${FILENAME}"
echo "Uploading to ${REMOTE_PATH}"
aws s3 cp "$LOCAL_FILE" "$REMOTE_PATH" --endpoint-url "$R2_ENDPOINT"

echo "Rotating local backups (keeping ${KEEP_LOCAL})"
ls -1t "$BACKUP_DIR"/*.enc 2>/dev/null | tail -n +$((KEEP_LOCAL + 1)) | xargs -r -I {} rm -- {}

echo "Rotating remote backups (keeping ${KEEP_REMOTE})"
aws s3api list-objects \
  --bucket "$R2_BUCKET" \
  --prefix "${POSTGRES_CONTAINER_NAME}/" \
  --endpoint-url "$R2_ENDPOINT" \
  --query "Contents | sort_by(@,&LastModified) | reverse(@)[${KEEP_REMOTE}:].Key" \
  --output text \
  | while read -r key; do
      echo "Deleting: ${key}"
      aws s3 rm "s3://${R2_BUCKET}/${key}" --endpoint-url "$R2_ENDPOINT"
    done

echo "Backup complete: ${FILENAME}"
