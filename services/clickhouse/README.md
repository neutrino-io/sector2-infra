# ClickHouse

The `ClickHouse` service in the Railway project is **actually** the Railway-managed PostgreSQL (`ghcr.io/railwayapp-templates/postgres-ssl:18`) — the service name is misleading; the image is a Postgres template, not ClickHouse.

## What's actually here

- This directory is a **placeholder** for a future self-hosted ClickHouse deployment
- Today, the live data source is a separate Railway service running a Postgres image (named `ClickHouse` in the dashboard for legacy reasons)
- The Trino `clickhouse` catalog currently connects to **that** service via JDBC

## Future: self-hosted ClickHouse

If/when we migrate to a real ClickHouse instance, add a `[[services]]` block to `/railway.toml`:

```toml
[[services]]
name = "sector2-clickhouse"
dockerfilePath = "services/clickhouse/Dockerfile"
rootDirectory = "services/clickhouse"

[services.deploy]
startCommand = "/entrypoint.sh"
healthcheckPath = "/ping"
healthcheckTimeout = 5
restartPolicyType = "ON_FAILURE"
restartPolicyMaxRetries = 3

[services.deploy.env]
CLICKHOUSE_DB = "sector2"
CLICKHOUSE_USER = "default"
CLICKHOUSE_PASSWORD = "${{ secrets.CLICKHOUSE_PASSWORD }}"
```

Until then, no deployable files exist here — the actual service lives outside this repo.