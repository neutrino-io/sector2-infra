# sector2-infra

Railway infrastructure monorepo for the **Sector2** political intelligence platform.

## Quick links

- Architecture: `shared/docs/ARCHITECTURE.md`
- Deployment: `shared/docs/DEPLOYMENT.md`
- Operations: `shared/docs/OPERATIONS.md`
- Troubleshooting: `shared/docs/TROUBLESHOOTING.md`
- Security: `shared/docs/SECURITY.md`

## Services

| Path | Image | Purpose |
|---|---|---|
| `services/superset/` | apache/superset (custom Dockerfile) | BI dashboard UI |
| `services/trino/` | trinodb/trino:435 | Query engine (Iceberg REST + ClickHouse JDBC) |
| `services/clickhouse/` | (skeleton) | ClickHouse instance template (NOT deployed) |

## Secrets

All secrets live in Railway Variables (NOT in this repo):

- `ADMIN_USERNAME`, `ADMIN_PASSWORD` — Superset admin user
- `SECRET_KEY`, `SUPERSET_SECRET_KEY` — Superset + MCP JWT signing
- `POSTGRES_URL` — Superset metadata DB connection
- `REDIS_URL` — Superset cache + rate limiting (optional)
- `R2_CATALOG_TOKEN`, `R2_ACCESS_KEY`, `R2_SECRET_KEY` — Cloudflare R2 Data Catalog auth
- `CLICKHOUSE_HOST`, `CLICKHOUSE_PORT`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD` — Legacy voter roll DB

Template: `.env.example`

## Deployment

Single `railway.toml` at repo root declares all services via `[[services]]` blocks. Each service has its own `dockerfilePath` relative to repo root.

```bash
# Link to existing Railway project
cd /DATA/Development/Sector2/Sources/sector2-infra
railway link

# Deploy all services
railway up
```

## Tests

```bash
# After Trino deploys:
./services/trino/verify-iceberg.sh

# Full smoke test:
./shared/tools/verify-all.sh
```

## Conventions

- Each service has its own Dockerfile + config
- Shared docs live in `shared/docs/`
- Verification scripts live next to the service they test
- Secrets are NEVER committed (only `.env.example` template)

## Migration from apache-superset-railway

This repo was created 2026-07-30 by consolidating `apache-superset-railway` (Superset-only) + adding Trino service. See `docs/plans/2026-07-30-sector2-infra-refactor-proposal.md` (in sector2-core) for the full plan.

No functional changes to Superset — same Dockerfile, same config, same Railway service. Only organizational change: services moved into subdirectories under a root `railway.toml`.