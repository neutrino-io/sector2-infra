# Trino Query Engine

Distributed SQL query engine for the Sector2 BI tier.

## What it queries

| Catalog | Source | Purpose |
|---|---|---|
| `iceberg` | Cloudflare R2 Data Catalog (Apache Iceberg REST) | Production tabular data (election results, poststrat, etc.) |
| `clickhouse` | Railway ClickHouse instance (JDBC) | Historical voter roll data |

## Image

`trinodb/trino:483` (RHEL 10 base; no apt-get — pure-bash entrypoint substitutes `${VAR}` in catalog templates).

## Required Railway variables

Set in Railway dashboard → Variables (never commit):

```bash
# R2 Data Catalog (Iceberg REST + OAuth2)
R2_ICEBERG_REST_URI=https://catalog.cloudflarestorage.com/<account-id>/<bucket-name>
R2_ICEBERG_WAREHOUSE=<account-id>_<bucket-name>
R2_CATALOG_TOKEN=cfat_xxx               # from R2 dashboard → Data Catalog → tokens

# R2 S3 filesystem (for Iceberg data files)
R2_ACCESS_KEY=xxx                       # object-storage access key
R2_SECRET_KEY=xxx                       # object-storage secret key
R2_S3_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com

# ClickHouse JDBC catalog
CLICKHOUSE_HOST=clickhouse.railway.internal
CLICKHOUSE_PORT=8123
CLICKHOUSE_USER=clickhouse
CLICKHOUSE_PASSWORD=xxx                 # from Railway ClickHouse service Variables
```

The TOML-driven config is at [`/railway.toml`](../../railway.toml). All `${{ secrets.X }}` references are resolved by Railway at deploy time.

## Local dev

Use the existing `sector2-core` docker-compose:

```bash
cd /DATA/Development/Sector2/Sources/sector2-core
docker compose -f superset/docker-compose.yml up trino
```

## Verify

```bash
# Public URL (after deploy)
curl https://sector2-trino-production.up.railway.app/v1/info | jq

# Run verify-iceberg.sh inside the container
/tmp/railway ssh --service sector2-trino "/etc/trino/template/verify-iceberg.sh"
```

Expected: `SELECT COUNT(*) FROM iceberg.electoral.election_result` returns **53,687** rows.

## Architecture

Single-node deployment: `coordinator=true` + `node-scheduler.include-coordinator=true` in `template/trino-config/config.properties.template`. Sufficient for current load (single Superset user, low query volume).

For higher scale, split into separate coordinator + worker services — see comment block in `/railway.toml` for the pattern.