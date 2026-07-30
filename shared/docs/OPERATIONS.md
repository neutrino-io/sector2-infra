# Operations Guide

## Common tasks

### View logs

```bash
# Live tail
railway logs --service <service-name>

# Last 100 lines
railway logs --service <service-name> --lines 100

# Specific deployment
railway logs --service <service-name> --deployment <id>
```

### Restart a service

```bash
railway restart --service <service-name>
```

### Scale resources

```bash
# Memory limit
railway scale --service <service-name> --memory 2GB

# CPU limit
railway scale --service <service-name> --cpu 1
```

### Check service health

```bash
# Superset
curl -sS https://<your-superset-url>/health

# Trino
curl -sS http://<trino-url>/v1/info
```

## Monitoring

Railway provides built-in metrics (CPU, memory, network). For deeper observability:

| Signal | Source | Alert |
|---|---|---|
| Container OOM | Railway metrics | Memory > 90% for 5 min |
| Service down | Health check | 3 consecutive failures |
| Disk pressure | Volume usage | > 80% full |
| Slow queries | Trino query history | P95 > 30s |

## Backup

### Superset metadata

```bash
# Dump PostgreSQL
railway run --service superset pg_dump $POSTGRES_URL > superset-backup-$(date +%Y%m%d).sql
```

### ClickHouse (managed by Nematix — out of scope here)

Contact Nematix for ClickHouse backup policy.

### Iceberg tables (Cloudflare R2 — automatic)

R2 has versioning enabled by default. Data is replicated across multiple regions.

## Disaster recovery

| Scenario | Recovery |
|---|---|
| Service crash | Railway auto-restarts per `restartPolicyType = ON_FAILURE` |
| Service unhealthy | Manual redeploy via `railway up --service <name>` |
| Data loss (D1) | R2 bronze is source of truth; re-run migration scripts |
| Data loss (R2) | R2 versioning + replication; contact Cloudflare support |
| Total Railway outage | Wait for Railway to recover; no data loss |

## Rotating secrets

### R2 token rotation

```bash
# 1. Generate new token in Cloudflare Dashboard
# 2. Update Railway Variables:
railway variables --set R2_CATALOG_TOKEN=<new-token>
# 3. Restart services to pick up new env:
railway restart --service superset
railway restart --service sector2-trino
```

### Superset SECRET_KEY rotation

⚠️ **Breaking change** — rotating SECRET_KEY invalidates all existing JWTs.

```bash
# 1. Update SECRET_KEY in Railway Variables
# 2. Restart Superset
# 3. All users must log in again
```

## Maintenance windows

Recommended: **Sunday 04:00–06:00 UTC** (lowest usage window).

Steps for any maintenance deploy:
1. Announce in team channel (Discord #sector2-deploys)
2. `railway up --service <name>`
3. Monitor logs for 10 minutes
4. Verify health endpoints
5. Announce completion

## Capacity planning

Current scale (2026-07-30):
- Superset: 1 instance, 512MB RAM, low usage
- Trino: 1 instance, 1GB RAM (recommended for Iceberg queries)

Future triggers:
- > 10 concurrent Superset users → scale Superset to 2 instances
- > 100 Trino queries/hour → split Trino coordinator + worker
- Iceberg tables > 100 GB → add compaction + partition strategy review