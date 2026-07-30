# Security

## Threat model

| Threat | Mitigation |
|---|---|
| Credential leak via git | All secrets in Railway Variables, never in repo |
| Unauthorized Superset access | JWT auth required; bearer token in `Authorization` header |
| Unauthorized Iceberg access | R2 catalog token scope-limited to one bucket |
| SQL injection | Superset uses parameterized queries via SQLAlchemy |
| Man-in-the-middle | HTTPS enforced; Railway provides TLS termination |
| Denial of service | Railway provides basic DDoS protection (Cloudflare network) |
| Insider threat (developer) | Repo read-only access; Railway access via owner's account |

## Secrets management

### Storage
All secrets live in Railway Variables (NOT in repo).

| Secret | Owner | Rotation frequency |
|---|---|---|
| `ADMIN_PASSWORD` | Operator | Quarterly |
| `SECRET_KEY` | Operator | Yearly (breaking change) |
| `SUPERSET_SECRET_KEY` | Operator | Yearly |
| `POSTGRES_URL` | Railway-managed | Auto |
| `REDIS_URL` | Railway-managed | Auto |
| `R2_CATALOG_TOKEN` | Operator | Quarterly |
| `R2_ACCESS_KEY` | Operator | Quarterly |
| `R2_SECRET_KEY` | Operator | Quarterly |
| `CLICKHOUSE_PASSWORD` | Operator | Quarterly |

### Rotation procedure

```bash
# 1. Generate new secret (in respective dashboard)
# 2. Update Railway Variable
railway variables --set SECRET_NAME=<new-value>
# 3. Restart affected services
railway restart --service superset
# 4. Verify health
curl -sS https://<superset-url>/health
```

### Token revocation

R2 tokens: delete in Cloudflare Dashboard → R2 → API tokens → Delete.
PostgreSQL: rotate `POSTGRES_URL` (Railway handles automatically on plugin restart).

## Access control

### Superset roles

- **Admin** (operator only): full access including database config, user management
- **Alpha** (analyst): can create datasets + dashboards, query all catalogs
- **Gamma** (viewer): read-only access to published dashboards

### Railway access

- Only repo owner has Railway CLI access
- Service-specific tokens not used; all deploys via `railway up`

### R2 access

- R2 catalog token is bucket-scoped: only `gyhc40sdz8-ivj8v3841x-bronze-storage`
- Read-only access possible (use Admin Read Only template if no writes needed)
- IP allowlist: not configured (relies on token secrecy)

## Audit logging

- Railway logs: 30-day retention in dashboard
- Superset logs: query history, login events, chart edits
- Trino logs: query history with user attribution via `X-Trino-User` header

## Vulnerability disclosure

If you discover a security issue:
1. Do NOT commit the issue publicly
2. Email: [owner contact]
3. Include: reproduction steps, impact assessment, suggested fix

Response time: within 7 days for critical issues.