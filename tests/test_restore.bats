#!/usr/bin/env bats

load helpers

setup() {
  setup_test_env
  create_mock docker 'cat > /dev/null'
}

teardown() {
  teardown_test_env
}

@test "restore: fails without arguments" {
  cd "$TEST_DIR"
  run bash restore.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "restore: fails when backup file does not exist" {
  cd "$TEST_DIR"
  run bash restore.sh nonexistent.dump.gz.enc
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "restore: fails when backup.key is missing" {
  cd "$TEST_DIR"
  touch test_backup.dump.gz.enc
  rm -f backup.key
  run bash restore.sh test_backup.dump.gz.enc
  [ "$status" -eq 1 ]
  [[ "$output" == *"backup.key"* ]]
}

@test "restore: fails when .env is missing" {
  cd "$TEST_DIR"
  touch test_backup.dump.gz.enc
  rm -f .env
  run bash restore.sh test_backup.dump.gz.enc
  [ "$status" -eq 1 ]
  [[ "$output" == *".env"* ]]
}

@test "restore: runs full restore successfully" {
  cd "$TEST_DIR"
  # Create a fake encrypted gzipped backup
  echo "fake-data" | gzip | openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:./backup.key > test.dump.gz.enc

  create_mock docker 'cat > /dev/null; exit 0'

  run bash restore.sh test.dump.gz.enc
  [ "$status" -eq 0 ]
  [[ "$output" == *"Restore complete:"* ]]
}

@test "restore: outputs table name when restoring specific table" {
  cd "$TEST_DIR"
  echo "fake-data" | gzip | openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:./backup.key > test.dump.gz.enc

  create_mock docker 'cat > /dev/null; exit 0'

  run bash restore.sh test.dump.gz.enc users
  [ "$status" -eq 0 ]
  [[ "$output" == *"table: users"* ]]
}

@test "restore: passes table flag to docker exec" {
  cd "$TEST_DIR"
  echo "fake-data" | gzip | openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:./backup.key > test.dump.gz.enc

  create_mock docker 'echo "DOCKER_ARGS: $*" >> "${TEST_DIR}/docker.log"; cat > /dev/null'

  run bash restore.sh test.dump.gz.enc my_table
  [ "$status" -eq 0 ]
  grep -q "table=my_table" "$TEST_DIR/docker.log"
}

@test "restore: does not include table flag for full restore" {
  cd "$TEST_DIR"
  echo "fake-data" | gzip | openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:./backup.key > test.dump.gz.enc

  create_mock docker 'echo "DOCKER_ARGS: $*" >> "${TEST_DIR}/docker.log"; cat > /dev/null'

  run bash restore.sh test.dump.gz.enc
  [ "$status" -eq 0 ]
  ! grep -q "table=" "$TEST_DIR/docker.log"
}
