#!/usr/bin/env bats

load helpers

setup() {
  setup_test_env
  create_mock pg_dump 'cat /dev/null'
  create_mock gzip 'cat'
  create_mock openssl 'cat > "${@: -1}" 2>/dev/null || cat > /dev/null'
  create_mock aws 'true'
}

teardown() {
  teardown_test_env
}

@test "backup: fails without backup_dir argument" {
  cd "$TEST_DIR"
  run bash backup.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "backup: fails when backup.key is missing" {
  cd "$TEST_DIR"
  rm -f backup.key
  run bash backup.sh /tmp/backups
  [ "$status" -eq 1 ]
  [[ "$output" == *"backup.key"* ]]
}

@test "backup: fails when .env is missing" {
  cd "$TEST_DIR"
  rm -f .env
  run bash backup.sh /tmp/backups
  [ "$status" -eq 1 ]
  [[ "$output" == *".env"* ]]
}

@test "backup: creates backup directory if missing" {
  cd "$TEST_DIR"
  create_mock pg_dump 'echo "mock-data"'
  create_mock openssl 'cat'
  create_mock gzip 'cat'

  BACKUP_DEST="$TEST_DIR/new-backups"
  run bash backup.sh "$BACKUP_DEST"
  [ -d "$BACKUP_DEST" ]
}

@test "backup: creates backup file with expected naming" {
  cd "$TEST_DIR"
  create_mock pg_dump 'echo "mock-data"'
  create_mock openssl 'cat'
  create_mock gzip 'cat'

  BACKUP_DEST="$TEST_DIR/backups"
  mkdir -p "$BACKUP_DEST"
  run bash backup.sh "$BACKUP_DEST"
  [ "$status" -eq 0 ]

  local files
  files=$(ls "$BACKUP_DEST"/*.dump.gz.enc 2>/dev/null | wc -l)
  [ "$files" -ge 1 ]
}

@test "backup: filename contains database name from env" {
  cd "$TEST_DIR"
  create_mock pg_dump 'echo "mock-data"'
  create_mock openssl 'cat'
  create_mock gzip 'cat'

  BACKUP_DEST="$TEST_DIR/backups"
  mkdir -p "$BACKUP_DEST"
  run bash backup.sh "$BACKUP_DEST"
  [ "$status" -eq 0 ]

  local db_name
  db_name=$(grep '^POSTGRES_DB=' .env | cut -d= -f2)
  ls "$BACKUP_DEST" | grep -q "^${db_name}_"
}

@test "backup: outputs completion message" {
  cd "$TEST_DIR"
  create_mock pg_dump 'echo "mock-data"'
  create_mock openssl 'cat'
  create_mock gzip 'cat'

  BACKUP_DEST="$TEST_DIR/backups"
  run bash backup.sh "$BACKUP_DEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Backup complete:"* ]]
}

@test "backup: local retention removes oldest files" {
  cd "$TEST_DIR"
  create_mock pg_dump 'echo "mock-data"'
  create_mock openssl 'cat'
  create_mock gzip 'cat'

  # Override KEEP_LOCAL to 2
  sed -i.bak 's/^KEEP_LOCAL=.*/KEEP_LOCAL=2/' .env

  BACKUP_DEST="$TEST_DIR/backups"
  mkdir -p "$BACKUP_DEST"

  # Create 3 pre-existing "old" backups
  for i in 1 2 3; do
    touch "$BACKUP_DEST/app_db_2025010${i}_000000.dump.gz.enc"
    sleep 0.1
  done

  run bash backup.sh "$BACKUP_DEST"
  [ "$status" -eq 0 ]

  local count
  count=$(ls -1 "$BACKUP_DEST"/*.enc 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -le 2 ]
}

@test "backup: respects default KEEP_LOCAL when not set" {
  cd "$TEST_DIR"
  create_mock pg_dump 'echo "mock-data"'
  create_mock openssl 'cat'
  create_mock gzip 'cat'

  # Remove KEEP_LOCAL from env so default (5) is used
  sed -i.bak '/^KEEP_LOCAL=/d' .env

  BACKUP_DEST="$TEST_DIR/backups"
  mkdir -p "$BACKUP_DEST"

  for i in 1 2 3 4; do
    touch "$BACKUP_DEST/app_db_2025010${i}_000000.dump.gz.enc"
    sleep 0.1
  done

  run bash backup.sh "$BACKUP_DEST"
  [ "$status" -eq 0 ]

  local count
  count=$(ls -1 "$BACKUP_DEST"/*.enc 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -le 5 ]
}

@test "backup: calls aws upload with correct bucket path" {
  cd "$TEST_DIR"
  create_mock pg_dump 'echo "mock-data"'
  create_mock openssl 'cat'
  create_mock gzip 'cat'
  create_mock aws 'echo "AWS_CALL: $*" >> "${TEST_DIR}/aws.log"'

  BACKUP_DEST="$TEST_DIR/backups"
  run bash backup.sh "$BACKUP_DEST"
  [ "$status" -eq 0 ]

  grep -q "s3 cp" "$TEST_DIR/aws.log"
  grep -q "s3://postgres-backups/pg-database/" "$TEST_DIR/aws.log"
}
