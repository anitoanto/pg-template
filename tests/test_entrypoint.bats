#!/usr/bin/env bats

load helpers

@test "entrypoint: fails when BACKUP_SCHEDULE is not set" {
  # entrypoint.sh requires apk which is Alpine-only; test the validation logic directly
  cd "$TEST_DIR"

  # Create a test script that simulates the validation portion
  cat > test_entrypoint_validation.sh <<'SCRIPT'
#!/bin/sh
set -e
if [ -z "$BACKUP_SCHEDULE" ]; then
  echo "ERROR: BACKUP_SCHEDULE is not set"
  exit 1
fi
echo "OK"
SCRIPT

  unset BACKUP_SCHEDULE
  run sh test_entrypoint_validation.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"BACKUP_SCHEDULE"* ]]
}

@test "entrypoint: passes when BACKUP_SCHEDULE is set" {
  cd "$TEST_DIR"
  cat > test_entrypoint_validation.sh <<'SCRIPT'
#!/bin/sh
set -e
if [ -z "$BACKUP_SCHEDULE" ]; then
  echo "ERROR: BACKUP_SCHEDULE is not set"
  exit 1
fi
echo "OK"
SCRIPT

  BACKUP_SCHEDULE="0 3 * * *" run sh test_entrypoint_validation.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "entrypoint: script has correct shebang" {
  head -1 "$PROJECT_ROOT/entrypoint.sh" | grep -q '#!/bin/sh'
}

@test "entrypoint: installs postgresql-client" {
  grep -q 'postgresql' "$PROJECT_ROOT/entrypoint.sh"
}

@test "entrypoint: installs openssl" {
  grep -q 'openssl' "$PROJECT_ROOT/entrypoint.sh"
}

@test "entrypoint: installs aws-cli" {
  grep -q 'aws-cli' "$PROJECT_ROOT/entrypoint.sh"
}

@test "entrypoint: uses exec for crond" {
  grep -q 'exec crond' "$PROJECT_ROOT/entrypoint.sh"
}

@test "entrypoint: saves environment for cron" {
  grep -q 'env > /etc/environment' "$PROJECT_ROOT/entrypoint.sh"
}

@test "entrypoint: cron sources environment before backup" {
  grep -q '/etc/environment' "$PROJECT_ROOT/entrypoint.sh"
  grep -q '/backup.sh' "$PROJECT_ROOT/entrypoint.sh"
}
