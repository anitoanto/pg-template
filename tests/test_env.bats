#!/usr/bin/env bats

load helpers

@test "env.sample: exists" {
  [ -f "$PROJECT_ROOT/.env.sample" ]
}

@test "env.sample: contains all required variables" {
  for var in "${ENV_REQUIRED_VARS[@]}"; do
    grep -q "^${var}=" "$PROJECT_ROOT/.env.sample" || {
      echo "Missing: $var"
      return 1
    }
  done
}

@test "env.sample: no credentials in sample values" {
  local key_val
  key_val=$(grep '^AWS_ACCESS_KEY_ID=' "$PROJECT_ROOT/.env.sample" | cut -d= -f2)
  [[ -z "$key_val" || "$key_val" == "your-"* || "$key_val" == "changeme" ]]

  local secret_val
  secret_val=$(grep '^AWS_SECRET_ACCESS_KEY=' "$PROJECT_ROOT/.env.sample" | cut -d= -f2)
  [[ -z "$secret_val" || "$secret_val" == "your-"* || "$secret_val" == "changeme" ]]
}

@test "env.sample: BACKUP_SCHEDULE is valid cron expression" {
  local schedule
  schedule=$(grep '^BACKUP_SCHEDULE=' "$PROJECT_ROOT/.env.sample" | cut -d= -f2 | tr -d '"')
  local fields
  fields=$(echo "$schedule" | wc -w | tr -d ' ')
  [ "$fields" -eq 5 ]
}

@test "env.sample: DOCKER_EXTERNAL_NETWORK is boolean" {
  local val
  val=$(grep '^DOCKER_EXTERNAL_NETWORK=' "$PROJECT_ROOT/.env.sample" | cut -d= -f2)
  [[ "$val" == "true" || "$val" == "false" ]]
}

@test "env.sample: KEEP_LOCAL is a positive integer" {
  local val
  val=$(grep '^KEEP_LOCAL=' "$PROJECT_ROOT/.env.sample" | cut -d= -f2)
  [[ "$val" =~ ^[1-9][0-9]*$ ]]
}

@test "env.sample: KEEP_REMOTE is a positive integer" {
  local val
  val=$(grep '^KEEP_REMOTE=' "$PROJECT_ROOT/.env.sample" | cut -d= -f2)
  [[ "$val" =~ ^[1-9][0-9]*$ ]]
}
