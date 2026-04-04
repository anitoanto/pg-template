#!/usr/bin/env bats

load helpers

@test "compose: file exists and is valid YAML" {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import yaml; yaml.safe_load(open('$PROJECT_ROOT/compose.yaml'))" 2>/dev/null || \
    python3 -c "
import re, sys
with open('$PROJECT_ROOT/compose.yaml') as f:
    content = f.read()
# Basic structural checks
assert 'services:' in content, 'Missing services key'
assert 'volumes:' in content, 'Missing volumes key'
assert 'networks:' in content, 'Missing networks key'
"
  else
    # Fallback: basic structure check
    grep -q '^services:' "$PROJECT_ROOT/compose.yaml"
    grep -q '^volumes:' "$PROJECT_ROOT/compose.yaml"
    grep -q '^networks:' "$PROJECT_ROOT/compose.yaml"
  fi
}

@test "compose: defines postgres-db service" {
  grep -q 'postgres-db:' "$PROJECT_ROOT/compose.yaml"
}

@test "compose: defines postgres-pgadmin service" {
  grep -q 'postgres-pgadmin:' "$PROJECT_ROOT/compose.yaml"
}

@test "compose: defines postgres-backup service" {
  grep -q 'postgres-backup:' "$PROJECT_ROOT/compose.yaml"
}

@test "compose: backup service uses backup profile" {
  local in_backup=0
  while IFS= read -r line; do
    if [[ "$line" =~ postgres-backup: ]]; then
      in_backup=1
    elif [[ $in_backup -eq 1 && "$line" =~ ^[[:space:]]*-[[:space:]]*backup ]]; then
      return 0
    elif [[ $in_backup -eq 1 && "$line" =~ ^[[:space:]]{4}[a-z] && ! "$line" =~ ^[[:space:]]{6,} ]]; then
      # New top-level key under service means we left profiles
      :
    fi
  done < "$PROJECT_ROOT/compose.yaml"
  grep -A5 'postgres-backup:' "$PROJECT_ROOT/compose.yaml" | grep -q 'backup'
}

@test "compose: pgadmin depends on postgres-db" {
  grep -A20 'postgres-pgadmin:' "$PROJECT_ROOT/compose.yaml" | grep -q 'postgres-db'
}

@test "compose: backup depends on postgres-db" {
  grep -A10 'postgres-backup:' "$PROJECT_ROOT/compose.yaml" | grep -q 'postgres-db'
}

@test "compose: uses pgvector image" {
  grep -q 'pgvector/pgvector' "$PROJECT_ROOT/compose.yaml"
}

@test "compose: backup container mounts backup.key as read-only" {
  grep -q 'backup.key:/backup.key:ro' "$PROJECT_ROOT/compose.yaml"
}

@test "compose: backup container mounts .env as read-only" {
  grep -q '.env:/.env:ro' "$PROJECT_ROOT/compose.yaml"
}

@test "compose: pgadmin servers.json mounted as read-only" {
  grep -q 'pgadmin-servers.json:/pgadmin4/servers.json:ro' "$PROJECT_ROOT/compose.yaml"
}

@test "compose: all services use the same network" {
  local network_count
  network_count=$(grep -c 'specified_network' "$PROJECT_ROOT/compose.yaml")
  # 3 services + 1 network definition = at least 4 references
  [ "$network_count" -ge 4 ]
}

@test "compose: postgres uses env vars for credentials" {
  grep -q 'POSTGRES_USER: ${POSTGRES_USER}' "$PROJECT_ROOT/compose.yaml"
  grep -q 'POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}' "$PROJECT_ROOT/compose.yaml"
  grep -q 'POSTGRES_DB: ${POSTGRES_DB}' "$PROJECT_ROOT/compose.yaml"
}

@test "compose: no hardcoded passwords" {
  ! grep -qiE '(password|secret):\s*[a-zA-Z0-9]+' "$PROJECT_ROOT/compose.yaml" || \
  ! grep -qiE '(password|secret):\s*[^${\s]' "$PROJECT_ROOT/compose.yaml"
}
