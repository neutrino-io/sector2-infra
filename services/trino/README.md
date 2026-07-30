# Trino Query Engine

Distributed SQL query engine for the Sector2 BI tier.

## What it queries

| Catalog | Source | Purpose |
|---|---|---|
| `iceberg` | Cloudflare R2 Data Catalog (Apache Iceberg REST) | Production tabular data (election results, poststrat, etc.) |
| `clickhouse` | Railway ClickHouse instance (legacy) | Historical voter roll data |
| `mart` | Local DuckDB Parquet files (dev only) | Mock data for local dev/CI |

## Image

`trinodb/trino:435` (Iceberg connector bundled since 404)

## Required environment variables

```bash
R2_ICEBERG_REST_URI=https://catalog.cloudflarestorage.com/203a605533f37eb35da80dcf03a7bed6/gyhc40sdz8-ivj8v3841x-bronze-storage
R2_CATALOG_TOKEN=<admin-read-write-token-from-r2-dashboard>
R2_ACCESS_KEY=<object-read-write-access-key>
R2_SECRET_KEY=<object-read-write-secret>
R2_S3_ENDPOINT=https://203a605533f37eb35da80dcf03a7bed6.r2.cloudflarestorage.com

CLICKHOUSE_HOST=<clickhouse.railway.internal>
CLICKHOUSE_PORT=9000
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=<from-clickhouse-plugin>
```

## Local dev

```bash
# Run with the existing sector2-core docker-compose
cd /DATA/Development/Sector2/Sources/sector2-core
docker compose -f superset/docker-compose.yml up trino
```

## Verify

```bash
# After deploy, run:
./verify-iceberg.sh
# Expected output:
#   [5] Row count: 53,687 (for electoral.election_result)
```

## Production deployment

```bash
# 1. Add to existing Railway project
railway up --service sector2-trino

# 2. Set env vars in Railway dashboard:
#    R2_ICEBERG_REST_URI, R2_CATALOG_TOKEN, R2_ACCESS_KEY, R2_SECRET_KEY, R2_S3_ENDPOINT
#    CLICKHOUSE_HOST, CLICKHOUSE_PORT, CLICKHOUSE_USER, CLICKHOUSE_PASSWORD

# 3. Verify
railway run --service sector2-trino ./verify-iceberg.sh
```

## Architecture note

This service uses Trino's all-in-one mode (coordinator + worker in one JVM).
For high-load production, split into coordinator + worker services:

```toml
[[services]]
name = "trino-coordinator"
dockerfilePath = "services/trino/Dockerfile"
[services.deploy]
startCommand = "/etc/trino/bin/run-trino"

[[services]]
name = "trino-worker"
dockerfilePath = "services/trino/Dockerfile"
[services.deploy]
startCommand = "/etc/trino/bin/run-trino --worker"
```

But for current scale (single Superset user, low query volume), single-node is sufficient.