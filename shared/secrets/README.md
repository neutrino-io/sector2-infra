# Secrets Management

## Where secrets live

**Production secrets**: Railway Variables dashboard.

**Local dev secrets**: `.env` file in this directory (gitignored).

**Never**: committed to git.

## Template

See `.env.example` in this directory for the full template.

```bash
# Copy template to .env (gitignored)
cp .env.example .env

# Edit with real values
vim .env

# Load into current shell
source .env
```

## Secret categories

| Category | Examples | Storage |
|---|---|---|
| Superset admin | `ADMIN_USERNAME`, `ADMIN_PASSWORD` | Railway Variables |
| Superset secrets | `SECRET_KEY`, `SUPERSET_SECRET_KEY` | Railway Variables |
| Database URIs | `POSTGRES_URL`, `REDIS_URL` | Railway Variables (auto-managed for plugins) |
| Cloudflare R2 | `R2_CATALOG_TOKEN`, `R2_ACCESS_KEY`, `R2_SECRET_KEY` | Railway Variables |
| ClickHouse | `CLICKHOUSE_HOST`, `CLICKHOUSE_PORT`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD` | Railway Variables |

## Rotation

See `shared/docs/SECURITY.md` for the full rotation procedure.

## What goes in Railway (not .env)

| Name | Source |
|---|---|
| `R2_ICEBERG_REST_URI` | Hardcoded constant (account-specific) |
| `R2_S3_ENDPOINT` | Hardcoded constant (account-specific) |

These are not secrets — they are deployment constants specific to the Cloudflare account. They live in `railway.toml` as plain strings, not in `.env.example`.