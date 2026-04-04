#!/bin/bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <backup.dump.gz.enc> [table_name]"
  exit 1
fi

BACKUP_FILE="$1"
TABLE_NAME="${2:-}"

for required_file in "$BACKUP_FILE" ./backup.key ./.env; do
  if [ ! -f "$required_file" ]; then
    echo "ERROR: ${required_file} not found"
    exit 1
  fi
done

set -a
. ./.env
set +a

echo "Restoring from ${BACKUP_FILE}${TABLE_NAME:+ (table: ${TABLE_NAME})}"

openssl enc -d -aes-256-cbc -pbkdf2 -pass file:./backup.key -in "$BACKUP_FILE" \
  | gunzip \
  | docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$POSTGRES_CONTAINER_NAME" \
      pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists \
      ${TABLE_NAME:+--table="$TABLE_NAME"}

echo "Restore complete: ${BACKUP_FILE}${TABLE_NAME:+ (table: ${TABLE_NAME})}"
