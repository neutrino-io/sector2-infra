# Superset Service

Apache Superset BI dashboard UI for Sector2.

## What this service does

- Hosts the web UI for creating/viewing dashboards
- Stores chart + dashboard definitions in PostgreSQL
- Executes SQL queries via connected databases (Trino, ClickHouse, R2 SQL)
- Exposes REST API at `/api/v1/`
- Exposes MCP at `/mcp` (requires JWT)

## Source

Refactored from `apache-superset-railway/` (now archived). Same Dockerfile + same config; only organizational change is the new directory structure.

## Railway deployment notes

**Critical: Do NOT set `healthcheckPath` on this service.**

Railway's bash session manager kills the container after ~6 minutes when a custom health check path is configured on an ASGI app with a custom ProxyRouter. The `asgi_app.py` exposes `/health` directly (returns 200 OK), but configuring Railway's deploy-time health check to probe it triggers the session killer.

Required service config:
```toml
[deploy]
startCommand = "./superset_init.sh"
healthcheckPath = ""          # do NOT set /health here
healthcheckTimeout = null     # disable deploy-time health probe
```

Plus environment variable:
```bash
PORT = "8088"                 # uvicorn binds to 8088; Railway edge needs to know
```

Root cause discovered by deploying the original `apache-superset-railway` repo side-by-side and observing identical failure pattern (container killed at ~6 min mark with "Session terminated, killing shell..."). The platform-level timeout, not the code, was the culprit. Removing the deploy-time health probe fixed it; the in-app `/health` endpoint is still functional for any external monitor that wants to use it.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | apache/superset base + ClickHouse drivers + FastMCP + Pillow |
| `superset_init.sh` | Bootstrap script (PostgreSQL connectivity check, admin creation, server start) |
| `asgi_app.py` | Flask + FastMCP ASGI wrapper (single port serves both UI and MCP, includes /health) |
| `superset_config.py` | All Superset config (PostgreSQL, ClickHouse, MCP, Redis) |
| `db_upgrade_safe.py` | Idempotent DB migration |
| `sitecustomize.py` | FAB 5.0.2 boot-bug patch (auto-loaded) |
| `clickhouse_railway_engine.py` | ClickHouse connection helpers |
| `verify-config.sh` | Validate configuration |
| `verify_clickhouse.py` | Test ClickHouse connectivity |
| `railway.toml.original` | Original railway.toml (kept for diff reference) |

## Required environment variables

```bash
ADMIN_USERNAME=admin
ADMIN_EMAIL=admin@sector2.local
ADMIN_PASSWORD=<password>
SECRET_KEY=<32-char-secret>
SUPERSET_SECRET_KEY=<32-char-secret>
SQLALCHEMY_DATABASE_URI=postgresql://<user>:<pass>@<host>:<port>/<db>
PORT=8088
REDIS_URL=redis://...  # optional
```

## Local dev

```bash
docker build -t sector2-superset .
docker run -p 8088:8088 \
  -e ADMIN_USERNAME=admin \
  -e ADMIN_PASSWORD=admin \
  -e SQLALCHEMY_DATABASE_URI=sqlite:////tmp/superset.db \
  sector2-superset
```

Open http://localhost:8088, log in with admin/admin.

## Database connection setup (via UI)

After deploying Superset, add databases via **Data → Databases**:

### Trino (Iceberg)

```
SQLAlchemy URI: trino://sector2-trino.railway.internal:8080/iceberg/electoral
```

Tables will appear: `election_result` (and any future Iceberg tables).

### ClickHouse (legacy voter roll)

```
SQLAlchemy URI: clickhouse+native://default:<password>@clickhouse.railway.internal:9000/sector2
```

Tables: `election_pahang`, `district`, etc.

## Verifying

```bash
curl -sS https://<your-superset-url>/health
# → "OK"

# Login (replace <password>):
JWT=$(curl -sS -X POST https://<your-superset-url>/api/v1/security/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"<password>","provider":"db"}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")

# List databases
curl -sS https://<your-superset-url>/api/v1/database/ \
  -H "Authorization: Bearer $JWT" | python3 -m json.tool
```
