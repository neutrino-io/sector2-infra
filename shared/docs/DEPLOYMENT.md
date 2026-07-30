# Deployment Guide

## First-time setup (Railway)

### 1. Create Railway project (if not exists)

The existing Railway project (hosting the current Superset) is the deployment target. **Do not create a new project.**

### 2. Link this repo to the existing project

```bash
cd /DATA/Development/Sector2/Sources/sector2-infra
railway link --project <existing-project-id>
```

### 3. Set environment variables

In Railway dashboard → project → Variables → **shared variables**:

| Name | Value | Service scope |
|---|---|---|
| `R2_CATALOG_TOKEN` | `<admin-read-write-token>` | superset, sector2-trino |
| `R2_ACCESS_KEY` | `<access-key>` | superset, sector2-trino |
| `R2_SECRET_KEY` | `<secret-key>` | superset, sector2-trino |
| `CLICKHOUSE_HOST` | `<clickhouse.railway.internal>` | sector2-trino |
| `CLICKHOUSE_PORT` | `9000` | sector2-trino |
| `CLICKHOUSE_USER` | `default` | sector2-trino |
| `CLICKHOUSE_PASSWORD` | `<password>` | sector2-trino |
| `SECRET_KEY` | `<32-char-secret>` | superset |
| `SUPERSET_SECRET_KEY` | `<32-char-secret>` | superset |
| `ADMIN_USERNAME` | `admin` | superset |
| `ADMIN_EMAIL` | `<email>` | superset |
| `ADMIN_PASSWORD` | `<password>` | superset |
| `POSTGRES_URL` | `<from-postgres-plugin>` | superset |
| `REDIS_URL` | `<from-redis-plugin>` (optional) | superset |

Generate secret keys:

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

### 4. Deploy superset

```bash
# First-time: deploy (creates service if not exists, or redeploys if exists)
railway up --service superset

# Wait for build + health check
railway logs --service superset
```

### 5. Deploy Trino (NEW)

```bash
railway up --service sector2-trino
railway logs --service sector2-trino
```

### 6. Verify Iceberg

```bash
# From your local machine with the JWT
railway run --service sector2-trino ./verify-iceberg.sh
# Expected: 53,687 rows in electoral.election_result
```

### 7. Add Trino database to Superset

In Superset UI:
1. Data → Databases → + Database
2. SQLAlchemy URI: `trino://sector2-trino.railway.internal:8080/iceberg/electoral`
3. Test connection
4. Save

## Day-to-day deploys

```bash
# After making code changes:
railway up --service <service-name>
```

Railway auto-detects the affected service from changed files in monorepo.

## Rollback

```bash
# Roll back to previous deployment
railway rollback --service <service-name>
```

Or via Railway dashboard → service → Deployments → click previous deploy → Redeploy.