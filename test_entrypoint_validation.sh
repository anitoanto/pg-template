#!/bin/sh
set -e
if [ -z "$BACKUP_SCHEDULE" ]; then
  echo "ERROR: BACKUP_SCHEDULE is not set"
  exit 1
fi
echo "OK"
