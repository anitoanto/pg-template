# Developer Guide

## Prerequisites

- Docker & Docker Compose
- Bash / Zsh
- [bats-core](https://github.com/bats-core/bats-core) (for tests)

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

Install bats:

```sh
brew install bats-core   # macOS
# or: apt install bats   # Debian/Ubuntu
```

Run:

```sh
bats tests/
```

Tests use mock binaries for `pg_dump`, `aws`, `docker`, etc. No running containers or cloud credentials required.
