#!/bin/sh
set -e

apk add --no-cache \
  postgresql18-client \
  gzip \
  openssl \
  aws-cli \
  bash

if [ -z "$BACKUP_SCHEDULE" ]; then
  echo "ERROR: BACKUP_SCHEDULE is not set"
  exit 1
fi

env > /etc/environment

echo "$BACKUP_SCHEDULE /bin/sh -c '. /etc/environment && cd / && /backup.sh /backups' >> /logs/backup.log 2>&1" \
  | crontab -

echo "Cron schedule: ${BACKUP_SCHEDULE}"
exec crond -f -l 6
