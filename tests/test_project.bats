#!/usr/bin/env bats

load helpers

@test "scripts: all shell scripts have shebang" {
  for script in backup.sh restore.sh init.sh entrypoint.sh; do
    head -1 "$PROJECT_ROOT/$script" | grep -qE '^#!/bin/(ba)?sh' || {
      echo "Missing shebang in $script"
      return 1
    }
  done
}

@test "scripts: all shell scripts use set -e" {
  for script in backup.sh restore.sh init.sh entrypoint.sh; do
    grep -q 'set -e' "$PROJECT_ROOT/$script" || {
      echo "Missing set -e in $script"
      return 1
    }
  done
}

@test "scripts: backup and restore use strict mode" {
  for script in backup.sh restore.sh; do
    grep -q 'set -euo pipefail' "$PROJECT_ROOT/$script" || {
      echo "Missing strict mode in $script"
      return 1
    }
  done
}

@test "scripts: all scripts are executable or have valid shebang" {
  for script in backup.sh restore.sh init.sh entrypoint.sh; do
    local path="$PROJECT_ROOT/$script"
    [[ -x "$path" ]] || head -1 "$path" | grep -qE '^#!' || {
      echo "$script is neither executable nor has shebang"
      return 1
    }
  done
}

@test "gitignore: excludes .env" {
  grep -q '^\.env$' "$PROJECT_ROOT/.gitignore"
}

@test "gitignore: excludes backup.key" {
  grep -q 'backup\.key' "$PROJECT_ROOT/.gitignore"
}

@test "gitignore: excludes backup files" {
  grep -q 'backups' "$PROJECT_ROOT/.gitignore"
}

@test "gitignore: excludes data directory" {
  grep -q '\-data' "$PROJECT_ROOT/.gitignore"
}
