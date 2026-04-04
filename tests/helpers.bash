#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

setup_test_env() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  cp "$PROJECT_ROOT"/backup.sh "$TEST_DIR/"
  cp "$PROJECT_ROOT"/restore.sh "$TEST_DIR/"
  cp "$PROJECT_ROOT"/init.sh "$TEST_DIR/"
  cp "$PROJECT_ROOT"/entrypoint.sh "$TEST_DIR/"
  cp "$PROJECT_ROOT"/.env.sample "$TEST_DIR/.env"
  echo "test-encryption-key" > "$TEST_DIR/backup.key"

  export PATH="$TEST_DIR/mocks:$PATH"
  mkdir -p "$TEST_DIR/mocks"
}

teardown_test_env() {
  rm -rf "$TEST_DIR"
}

create_mock() {
  local cmd="$1"
  local body="${2:-exit 0}"
  cat > "$TEST_DIR/mocks/$cmd" <<EOF
#!/bin/bash
$body
EOF
  chmod +x "$TEST_DIR/mocks/$cmd"
}

ENV_REQUIRED_VARS=(
  POSTGRES_CONTAINER_NAME
  POSTGRES_PORT
  POSTGRES_USER
  POSTGRES_PASSWORD
  POSTGRES_DB
  PGADMIN_PORT
  PGADMIN_DEFAULT_EMAIL
  PGADMIN_DEFAULT_PASSWORD
  HOST_UID
  HOST_GID
  DOCKER_NETWORK_NAME
  DOCKER_EXTERNAL_NETWORK
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  AWS_DEFAULT_REGION
  R2_BUCKET
  R2_ENDPOINT
  KEEP_LOCAL
  KEEP_REMOTE
  BACKUP_SCHEDULE
)
