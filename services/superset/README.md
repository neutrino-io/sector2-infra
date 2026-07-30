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

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | apache/superset base + ClickHouse drivers + FastMCP + Pillow |
| `superset_init.sh` | Bootstrap script (PostgreSQL connectivity check, admin creation, server start) |
| `asgi_app.py` | Flask + FastMCP ASGI wrapper (single port serves both UI and MCP) |
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