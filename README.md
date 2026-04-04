# pg-template

Docker Compose template for PostgreSQL with [pgvector](https://github.com/pgvector/pgvector), pgAdmin, and encrypted automated backups to S3/R2.

## Features

- PostgreSQL 18 with pgvector extension
- pgAdmin 4 web interface
- AES-256-CBC encrypted backups with gzip compression
- Scheduled backups via cron (Alpine sidecar container)
- Upload to S3-compatible storage (Cloudflare R2, AWS S3, MinIO)
- Local and remote backup retention policies
- Single-table or full database restore

## Quick Start

```sh
cp .env.sample .env           # configure your environment
openssl rand -base64 32 > backup.key  # generate encryption key
sh init.sh                    # create directories and pgadmin config
docker compose up -d          # start postgres + pgadmin
```

pgAdmin will be available at `http://localhost:<PGADMIN_PORT>`.

## Backups

Start the backup sidecar:

```sh
docker compose --profile backup up -d
```

Backups run on the schedule defined by `BACKUP_SCHEDULE` in `.env`. Files are encrypted with `backup.key` and uploaded to your configured S3/R2 bucket.

## Restore

```sh
# Full database restore
sh restore.sh backups/<filename>.dump.gz.enc

# Single table restore
sh restore.sh backups/<filename>.dump.gz.enc <table_name>
```

## Configuration

See [.env.sample](.env.sample) for all available options.

## Support

If you find this project useful, please consider starring the repository on GitHub, Thanks :)

## License

[MIT](LICENSE)
