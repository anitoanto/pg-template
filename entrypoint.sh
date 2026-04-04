#!/bin/sh
set -e

# -------------------------
# Install required packages
# -------------------------
apk add --no-cache \
  postgresql18-client \
  gzip \
  openssl \
  aws-cli \
  bash

# -------------------------
# Set up cron job
# -------------------------
# BACKUP_SCHEDULE must be a standard 5-field cron expression
# e.g. "0 3 * * *" for daily at 3 AM
if [ -z "$BACKUP_SCHEDULE" ]; then
  echo "ERROR: BACKUP_SCHEDULE env var is not set"
  exit 1
fi

# Write environment to a file so cron jobs can access it
env > /etc/environment

# Create crontab entry
# The wrapper sources the environment and runs from / where backup.key and .env are mounted
echo "$BACKUP_SCHEDULE /bin/sh -c '. /etc/environment && cd / && /backup.sh /backups' >> /var/log/backup.log 2>&1" \
  | crontab -

echo "Cron schedule set: $BACKUP_SCHEDULE"
echo "Starting crond..."

# Run crond in foreground
exec crond -f -l 6
