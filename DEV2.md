# Developer Guide

## Prerequisites

- Docker & Docker Compose
- Bash / Zsh

## Setup

```sh
cp .env.sample .env
openssl rand -base64 32 > backup.key
sh init.sh
```

## Run

```sh
# Start postgres + pgAdmin
docker compose up -d

# Start with backup sidecar
docker compose --profile backup up -d

# Stop everything
docker compose --profile backup down
```

## Tests

For comprehensive testing with real Docker containers, PostgreSQL, pgAdmin, and MinIO (S3 mock):

Prerequisites:
- Docker & Docker Compose
- openssl
- curl

Run:

```sh
bash tests/integration_test.sh
```

This spins up a complete environment, inserts test data, creates an encrypted backup, drops data, and verifies the restore works correctly.
