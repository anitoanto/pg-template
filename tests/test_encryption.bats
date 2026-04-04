#!/usr/bin/env bats

load helpers

@test "encryption: backup and restore round-trip preserves data" {
  local test_data="Hello, this is test data for encryption round-trip"
  local key_file="$TEST_DIR/backup.key"
  local encrypted="$TEST_DIR/test.dump.gz.enc"

  echo "test-key-12345" > "$key_file"

  echo "$test_data" \
    | gzip \
    | openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:"$key_file" \
    > "$encrypted"

  local decrypted
  decrypted=$(openssl enc -d -aes-256-cbc -pbkdf2 -pass file:"$key_file" -in "$encrypted" | gunzip)

  [ "$decrypted" = "$test_data" ]
}

@test "encryption: wrong key fails decryption" {
  local key_file="$TEST_DIR/backup.key"
  local wrong_key="$TEST_DIR/wrong.key"
  local encrypted="$TEST_DIR/test.dump.gz.enc"

  echo "correct-key" > "$key_file"
  echo "wrong-key" > "$wrong_key"

  echo "secret data" \
    | gzip \
    | openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:"$key_file" \
    > "$encrypted"

  run bash -c "openssl enc -d -aes-256-cbc -pbkdf2 -pass file:'$wrong_key' -in '$encrypted' 2>/dev/null | gunzip 2>/dev/null"
  [ "$status" -ne 0 ]
}

@test "encryption: encrypted file is not plaintext" {
  local key_file="$TEST_DIR/backup.key"
  local encrypted="$TEST_DIR/test.dump.gz.enc"

  echo "test-key" > "$key_file"
  echo "this is plaintext data" \
    | gzip \
    | openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:"$key_file" \
    > "$encrypted"

  ! grep -q "plaintext" "$encrypted"
}

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}
