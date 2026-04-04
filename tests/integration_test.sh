#!/bin/bash
###############################################################################
# Integration test for pg-template
#
# Spins up real Docker containers (PostgreSQL, pgAdmin, MinIO as S3 mock),
# inserts data, creates an encrypted backup via backup.sh, drops data,
# restores via restore.sh, and verifies everything round-trips correctly.
#
# Prerequisites: Docker, Docker Compose, openssl, curl
# Usage:  bash tests/integration_test.sh
###############################################################################
set -euo pipefail

#──────────────────────────── Configuration ────────────────────────────────────
# Use unique names / ports so tests don't collide with real deployments.
TEST_PREFIX="pgtest-$$"                     # PID-based isolation
POSTGRES_PORT=15432
PGADMIN_PORT=15050
MINIO_API_PORT=19000
MINIO_CONSOLE_PORT=19001
MINIO_ROOT_USER="minioadmin"
MINIO_ROOT_PASSWORD="minioadmin"
R2_BUCKET="test-backups"

# Colours (if terminal supports them)
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

#──────────────────────────── Helpers ──────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf "${GREEN}  ✔ %s${NC}\n" "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf "${RED}  ✘ %s${NC}\n" "$1"; }
info() { printf "${YELLOW}▶ %s${NC}\n" "$1"; }

# Wait for a TCP port to accept connections.  Retries every 2 s, up to $2 times.
wait_for_port() {
  local host="$1" port="$2" retries="${3:-30}" i=0
  while ! nc -z "$host" "$port" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge "$retries" ]; then
      echo "Timed out waiting for ${host}:${port}" >&2
      return 1
    fi
    sleep 2
  done
}

# Run psql against the test database via docker exec.
psql_run() {
  docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$POSTGRES_CONTAINER_NAME" \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAq "$@"
}

#──────────────────────────── Workspace setup ─────────────────────────────────
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR=$(mktemp -d)
trap 'cleanup' EXIT

cleanup() {
  info "Cleaning up …"
  cd "$WORK_DIR" 2>/dev/null || true
  # Bring down all services including backup profile
  docker compose --profile backup down -v --remove-orphans 2>/dev/null || true
  # Also stop the MinIO container
  docker rm -f "${TEST_PREFIX}-minio" 2>/dev/null || true
  # Remove the test network if we created one
  docker network rm "${TEST_PREFIX}-net" 2>/dev/null || true
  rm -rf "$WORK_DIR"
  printf "\n"
  info "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
  if [ "$FAIL_COUNT" -gt 0 ]; then exit 1; fi
}

# Copy project files into the isolated work directory.
cp "$PROJECT_ROOT"/compose.yaml "$WORK_DIR/"
cp "$PROJECT_ROOT"/backup.sh    "$WORK_DIR/"
cp "$PROJECT_ROOT"/restore.sh   "$WORK_DIR/"
cp "$PROJECT_ROOT"/entrypoint.sh "$WORK_DIR/"
cp "$PROJECT_ROOT"/init.sh      "$WORK_DIR/"

cd "$WORK_DIR"

#──────────────────────────── .env ─────────────────────────────────────────────
POSTGRES_USER="testuser"
POSTGRES_PASSWORD="testpass_$(openssl rand -hex 4)"
POSTGRES_DB="testdb"
POSTGRES_CONTAINER_NAME="${TEST_PREFIX}-db"

cat > .env <<EOF
POSTGRES_CONTAINER_NAME=${POSTGRES_CONTAINER_NAME}
POSTGRES_PORT=${POSTGRES_PORT}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
PGADMIN_PORT=${PGADMIN_PORT}
PGADMIN_DEFAULT_EMAIL=admin@example.com
PGADMIN_DEFAULT_PASSWORD=pgadmin_test
HOST_UID=$(id -u)
HOST_GID=$(id -g)
DOCKER_NETWORK_NAME=${TEST_PREFIX}-net
DOCKER_EXTERNAL_NETWORK=false
AWS_ACCESS_KEY_ID=${MINIO_ROOT_USER}
AWS_SECRET_ACCESS_KEY=${MINIO_ROOT_PASSWORD}
AWS_DEFAULT_REGION=us-east-1
R2_BUCKET=${R2_BUCKET}
R2_ENDPOINT=http://${TEST_PREFIX}-minio:9000
KEEP_LOCAL=5
KEEP_REMOTE=5
BACKUP_SCHEDULE="0 */12 * * *"
EOF

#──────────────────────────── Encryption key ──────────────────────────────────
openssl rand -base64 32 > backup.key

#──────────────────────────── init.sh ─────────────────────────────────────────
info "Running init.sh"
sh init.sh
[ -f pgadmin-servers.json ] && pass "init.sh created pgadmin-servers.json" \
                            || fail "init.sh did not create pgadmin-servers.json"
[ -d "${POSTGRES_CONTAINER_NAME}-data" ] && pass "init.sh created data directory" \
                                         || fail "init.sh did not create data directory"
[ -d backups ] && pass "init.sh created backups directory" \
              || fail "init.sh did not create backups directory"

###############################################################################
# 1. Start PostgreSQL + pgAdmin
###############################################################################
info "Starting PostgreSQL and pgAdmin"
docker compose up -d

info "Waiting for PostgreSQL to be ready"
wait_for_port 127.0.0.1 "$POSTGRES_PORT" 30
# Extra wait for postgres to finish its init
sleep 3
# Retry psql connection (pg may reject early connections)
for _attempt in $(seq 1 15); do
  if psql_run -c "SELECT 1;" >/dev/null 2>&1; then break; fi
  sleep 2
done

###############################################################################
# 2. Verify PostgreSQL is operational
###############################################################################
info "Testing PostgreSQL connectivity"
result=$(psql_run -c "SELECT 1;")
[ "$result" = "1" ] && pass "PostgreSQL responds to queries" \
                     || fail "PostgreSQL SELECT 1 returned: ${result}"

###############################################################################
# 3. Test pgvector extension
###############################################################################
info "Testing pgvector extension"
psql_run -c "CREATE EXTENSION IF NOT EXISTS vector;"
ext_check=$(psql_run -c "SELECT extname FROM pg_extension WHERE extname = 'vector';")
[ "$ext_check" = "vector" ] && pass "pgvector extension enabled" \
                             || fail "pgvector extension not found"

###############################################################################
# 4. Insert test data
###############################################################################
info "Inserting test data"

psql_run <<'SQL'
CREATE TABLE IF NOT EXISTS employees (
  id    SERIAL PRIMARY KEY,
  name  TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  dept  TEXT
);

INSERT INTO employees (name, email, dept) VALUES
  ('Alice',   'alice@test.com',   'Engineering'),
  ('Bob',     'bob@test.com',     'Marketing'),
  ('Charlie', 'charlie@test.com', 'Engineering'),
  ('Diana',   'diana@test.com',   'Finance');

CREATE TABLE IF NOT EXISTS embeddings (
  id        SERIAL PRIMARY KEY,
  content   TEXT,
  embedding vector(3)
);

INSERT INTO embeddings (content, embedding) VALUES
  ('hello world',  '[0.1, 0.2, 0.3]'),
  ('foo bar baz',  '[0.4, 0.5, 0.6]');
SQL

emp_count=$(psql_run -c "SELECT count(*) FROM employees;")
[ "$emp_count" = "4" ] && pass "Inserted 4 employees" \
                        || fail "Employee count: ${emp_count} (expected 4)"

vec_count=$(psql_run -c "SELECT count(*) FROM embeddings;")
[ "$vec_count" = "2" ] && pass "Inserted 2 vector embeddings" \
                        || fail "Embedding count: ${vec_count} (expected 2)"

###############################################################################
# 5. Query & validate data
###############################################################################
info "Querying data"

eng_count=$(psql_run -c "SELECT count(*) FROM employees WHERE dept = 'Engineering';")
[ "$eng_count" = "2" ] && pass "Filtered query: 2 engineers" \
                        || fail "Engineering count: ${eng_count} (expected 2)"

nearest=$(psql_run -c "SELECT content FROM embeddings ORDER BY embedding <-> '[0.1, 0.2, 0.3]' LIMIT 1;")
[ "$nearest" = "hello world" ] && pass "pgvector nearest-neighbour search works" \
                                || fail "Nearest neighbour returned: ${nearest}"

###############################################################################
# 6. Start MinIO (local S3 mock) and create the backup bucket
###############################################################################
info "Starting MinIO (S3 mock)"

# Create the docker network first if docker compose hasn't already
docker network inspect "${TEST_PREFIX}-net" >/dev/null 2>&1 || true

docker run -d --rm \
  --name "${TEST_PREFIX}-minio" \
  --network "${TEST_PREFIX}-net" \
  -p "${MINIO_API_PORT}:9000" \
  -p "${MINIO_CONSOLE_PORT}:9001" \
  -e "MINIO_ROOT_USER=${MINIO_ROOT_USER}" \
  -e "MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}" \
  minio/minio:latest server /data --console-address ":9001"

wait_for_port 127.0.0.1 "$MINIO_API_PORT" 20
sleep 2  # give MinIO a moment to finish startup

# Create the bucket via the MinIO client (no host aws-cli dependency)
docker run --rm --network "${TEST_PREFIX}-net" \
  --entrypoint sh minio/mc:latest -c "
    mc alias set myminio http://${TEST_PREFIX}-minio:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} && \
    mc mb myminio/${R2_BUCKET}
  " \
  && pass "Created S3 bucket '${R2_BUCKET}' on MinIO" \
  || fail "Could not create S3 bucket on MinIO"

###############################################################################
# 8. Run backup.sh (inside the container network, simulating the backup sidecar)
###############################################################################
info "Running encrypted backup"

# We run backup.sh inside a throwaway Alpine container that mirrors the real
# backup sidecar—same image, same network, same volumes—targeting MinIO.
docker run --rm \
  --network "${TEST_PREFIX}-net" \
  -v "$WORK_DIR/backup.sh:/backup.sh:ro" \
  -v "$WORK_DIR/backup.key:/backup.key:ro" \
  -v "$WORK_DIR/.env:/.env:ro" \
  -v "$WORK_DIR/backups:/backups" \
  -w / \
  alpine:3.23 sh -c '
    apk add --no-cache postgresql18-client gzip openssl aws-cli bash >/dev/null 2>&1
    bash /backup.sh /backups
  '

backup_file=$(ls -1t backups/*.enc 2>/dev/null | head -1)
if [ -n "$backup_file" ]; then
  pass "Backup file created: $(basename "$backup_file")"
else
  fail "No backup file found in backups/"
fi

# Verify the backup was uploaded to MinIO
remote_count=$(docker run --rm --network "${TEST_PREFIX}-net" \
  --entrypoint sh minio/mc:latest -c "
    mc alias set myminio http://${TEST_PREFIX}-minio:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} >/dev/null 2>&1
    mc ls myminio/${R2_BUCKET}/${POSTGRES_CONTAINER_NAME}/ 2>/dev/null | wc -l
  " | tr -d ' ')
[ "$remote_count" -ge 1 ] && pass "Backup uploaded to S3 (MinIO)" \
                           || fail "No backup found in S3 bucket"

###############################################################################
# 9. Verify backup file is actually encrypted (not plain SQL)
###############################################################################
info "Verifying backup encryption"

head_bytes=$(xxd -l 16 -p "$backup_file" 2>/dev/null)
# Encrypted OpenSSL files start with "Salted__" = 53616c7465645f5f
if echo "$head_bytes" | grep -q "^53616c7465645f5f"; then
  pass "Backup file is OpenSSL-encrypted (Salted__ header)"
else
  fail "Backup file does not look encrypted: ${head_bytes}"
fi

###############################################################################
# 10. Drop all test data
###############################################################################
info "Dropping test data to prepare for restore"

psql_run -c "DROP TABLE IF EXISTS employees CASCADE;"
psql_run -c "DROP TABLE IF EXISTS embeddings CASCADE;"

remaining=$(psql_run -c "SELECT count(*) FROM information_schema.tables WHERE table_name IN ('employees','embeddings') AND table_schema = 'public';")
[ "$remaining" = "0" ] && pass "Test tables dropped" \
                        || fail "Tables still present after drop: ${remaining}"

###############################################################################
# 11. Restore from backup using restore.sh
###############################################################################
info "Restoring from encrypted backup"

bash restore.sh "$backup_file"

###############################################################################
# 12. Verify restored data
###############################################################################
info "Verifying restored data"

restored_emp=$(psql_run -c "SELECT count(*) FROM employees;")
[ "$restored_emp" = "4" ] && pass "Restored 4 employees" \
                           || fail "Restored employee count: ${restored_emp} (expected 4)"

alice=$(psql_run -c "SELECT name FROM employees WHERE email = 'alice@test.com';")
[ "$alice" = "Alice" ] && pass "Alice record intact after restore" \
                        || fail "Alice lookup returned: ${alice}"

restored_vec=$(psql_run -c "SELECT count(*) FROM embeddings;")
[ "$restored_vec" = "2" ] && pass "Restored 2 vector embeddings" \
                           || fail "Restored embedding count: ${restored_vec} (expected 2)"

nearest_after=$(psql_run -c "SELECT content FROM embeddings ORDER BY embedding <-> '[0.1, 0.2, 0.3]' LIMIT 1;")
[ "$nearest_after" = "hello world" ] && pass "pgvector search works after restore" \
                                      || fail "Post-restore nearest neighbour: ${nearest_after}"

###############################################################################
# 13. Test single-table restore
###############################################################################
info "Testing single-table restore"

# Modify employees, then restore just that table
psql_run -c "DELETE FROM employees WHERE name = 'Alice';"
pre_restore=$(psql_run -c "SELECT count(*) FROM employees;")
[ "$pre_restore" = "3" ] && pass "Deleted Alice (3 employees remain)" \
                          || fail "Pre-restore count: ${pre_restore} (expected 3)"

bash restore.sh "$backup_file" employees

post_restore=$(psql_run -c "SELECT count(*) FROM employees;")
[ "$post_restore" = "4" ] && pass "Single-table restore recovered Alice (4 employees)" \
                           || fail "Post single-table restore count: ${post_restore} (expected 4)"

# Confirm embeddings were NOT affected by the single-table restore
vec_still=$(psql_run -c "SELECT count(*) FROM embeddings;")
[ "$vec_still" = "2" ] && pass "Embeddings table unaffected by single-table restore" \
                        || fail "Embeddings count after single-table restore: ${vec_still}"

###############################################################################
# 14. Test backup rotation (local retention)
###############################################################################
info "Testing local backup rotation"

# Create dummy old backups (KEEP_LOCAL=5, so 6th oldest should be pruned)
for i in $(seq 1 6); do
  touch "backups/${POSTGRES_DB}_2024010${i}_000000.dump.gz.enc"
done

# Run another backup which triggers rotation
docker run --rm \
  --network "${TEST_PREFIX}-net" \
  -v "$WORK_DIR/backup.sh:/backup.sh:ro" \
  -v "$WORK_DIR/backup.key:/backup.key:ro" \
  -v "$WORK_DIR/.env:/.env:ro" \
  -v "$WORK_DIR/backups:/backups" \
  -w / \
  alpine:3.23 sh -c '
    apk add --no-cache postgresql18-client gzip openssl aws-cli bash >/dev/null 2>&1
    bash /backup.sh /backups
  '

local_count=$(ls -1 backups/*.enc 2>/dev/null | wc -l | tr -d ' ')
[ "$local_count" -le 5 ] && pass "Local rotation keeps ≤ 5 backups (found ${local_count})" \
                          || fail "Local rotation: ${local_count} backups (expected ≤ 5)"

###############################################################################
# 15. Test remote backup rotation (KEEP_REMOTE)
###############################################################################
info "Testing remote backup rotation"

# Upload dummy old backups to MinIO to exceed KEEP_REMOTE (=5).
# There are already some remote backups from previous test runs.
# Add 5 more dummy files so total exceeds KEEP_REMOTE.
docker run --rm --network "${TEST_PREFIX}-net" \
  --entrypoint sh minio/mc:latest -c "
    mc alias set myminio http://${TEST_PREFIX}-minio:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} >/dev/null 2>&1
    for i in 1 2 3 4 5; do
      echo dummy | mc pipe myminio/${R2_BUCKET}/${POSTGRES_CONTAINER_NAME}/${POSTGRES_DB}_2023010\${i}_000000.dump.gz.enc
    done
  "

# Run another backup which triggers remote rotation
docker run --rm \
  --network "${TEST_PREFIX}-net" \
  -v "$WORK_DIR/backup.sh:/backup.sh:ro" \
  -v "$WORK_DIR/backup.key:/backup.key:ro" \
  -v "$WORK_DIR/.env:/.env:ro" \
  -v "$WORK_DIR/backups:/backups" \
  -w / \
  alpine:3.23 sh -c '
    apk add --no-cache postgresql18-client gzip openssl aws-cli bash >/dev/null 2>&1
    bash /backup.sh /backups
  '

remote_count_after=$(docker run --rm --network "${TEST_PREFIX}-net" \
  --entrypoint sh minio/mc:latest -c "
    mc alias set myminio http://${TEST_PREFIX}-minio:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} >/dev/null 2>&1
    mc ls myminio/${R2_BUCKET}/${POSTGRES_CONTAINER_NAME}/ 2>/dev/null | wc -l
  " | tr -d ' ')

[ "$remote_count_after" -le 5 ] && pass "Remote rotation keeps ≤ 5 backups (found ${remote_count_after})" \
                                 || fail "Remote rotation: ${remote_count_after} remote backups (expected ≤ 5)"

###############################################################################
# 16. Test pgAdmin accessibility (tested late to give it ample startup time)
###############################################################################
info "Testing pgAdmin"

# pgAdmin can take a long time to initialise; retry the HTTP check.
pgadmin_http="000"
for _pa in $(seq 1 30); do
  pgadmin_http=$(curl -sL -o /dev/null -w "%{http_code}" \
    --max-time 5 "http://127.0.0.1:${PGADMIN_PORT}/login" 2>/dev/null) || pgadmin_http="000"
  if [ "$pgadmin_http" = "200" ]; then break; fi
  sleep 3
done

if [ "$pgadmin_http" = "200" ]; then
  pass "pgAdmin login page returns HTTP 200"
else
  fail "pgAdmin HTTP status: ${pgadmin_http} (expected 200)"
fi

# Test pgAdmin health endpoint (version-independent)
health_response=$(curl -sL -o /dev/null -w "%{http_code}" --max-time 5 \
  "http://127.0.0.1:${PGADMIN_PORT}/misc/ping" 2>/dev/null) || health_response="000"

if [ "$health_response" = "200" ]; then
  pass "pgAdmin health endpoint (/misc/ping) returns HTTP 200"
else
  fail "pgAdmin health status: ${health_response} (expected 200)"
fi

###############################################################################
# 17. Verify containers are running with expected names
###############################################################################
info "Verifying container states"

for svc in "${POSTGRES_CONTAINER_NAME}" "${POSTGRES_CONTAINER_NAME}-pgadmin"; do
  state=$(docker inspect -f '{{.State.Running}}' "$svc" 2>/dev/null || echo "false")
  [ "$state" = "true" ] && pass "Container ${svc} is running" \
                         || fail "Container ${svc} is not running"
done

###############################################################################
# Summary
###############################################################################
printf "\n"
info "════════════════════════════════════════════════════════════"
info "  Integration tests complete: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
info "════════════════════════════════════════════════════════════"
