#!/usr/bin/env bats

load helpers

setup() {
  setup_test_env
  create_mock sudo '"$@"'
  create_mock chown 'true'
}

teardown() {
  teardown_test_env
}

@test "init: creates pgadmin-servers.json" {
  cd "$TEST_DIR"
  run sh init.sh
  [ "$status" -eq 0 ]
  [ -f ./pgadmin-servers.json ]
}

@test "init: pgadmin-servers.json contains correct host" {
  cd "$TEST_DIR"
  run sh init.sh
  [ "$status" -eq 0 ]

  local container_name
  container_name=$(grep '^POSTGRES_CONTAINER_NAME=' .env | cut -d= -f2)
  grep -q "\"Host\": \"${container_name}\"" ./pgadmin-servers.json
}

@test "init: pgadmin-servers.json contains correct username" {
  cd "$TEST_DIR"
  run sh init.sh
  [ "$status" -eq 0 ]

  local user
  user=$(grep '^POSTGRES_USER=' .env | cut -d= -f2)
  grep -q "\"Username\": \"${user}\"" ./pgadmin-servers.json
}

@test "init: pgadmin-servers.json is valid JSON" {
  cd "$TEST_DIR"
  sh init.sh

  if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool ./pgadmin-servers.json > /dev/null
  elif command -v jq >/dev/null 2>&1; then
    jq . ./pgadmin-servers.json > /dev/null
  else
    skip "No JSON validator available"
  fi
}

@test "init: creates data directory" {
  cd "$TEST_DIR"
  run sh init.sh
  [ "$status" -eq 0 ]

  local container_name
  container_name=$(grep '^POSTGRES_CONTAINER_NAME=' .env | cut -d= -f2)
  [ -d "./${container_name}-data" ]
}

@test "init: data directory has restricted permissions" {
  cd "$TEST_DIR"
  sh init.sh

  local container_name
  container_name=$(grep '^POSTGRES_CONTAINER_NAME=' .env | cut -d= -f2)
  local perms
  perms=$(stat -f '%Lp' "./${container_name}-data" 2>/dev/null || stat -c '%a' "./${container_name}-data" 2>/dev/null)
  [ "$perms" = "700" ]
}

@test "init: creates backups directory" {
  cd "$TEST_DIR"
  run sh init.sh
  [ "$status" -eq 0 ]
  [ -d ./backups ]
}

@test "init: is idempotent" {
  cd "$TEST_DIR"
  sh init.sh
  run sh init.sh
  [ "$status" -eq 0 ]
  [ -f ./pgadmin-servers.json ]
}
