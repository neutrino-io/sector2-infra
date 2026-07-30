# Troubleshooting

## Superset

### Login fails with "Fatal error" HTTP 500

**Symptom:** `POST /api/v1/security/login` returns `{"message":"Fatal error"}`

**Causes:**
1. `SQLALCHEMY_DATABASE_URI` missing or invalid → Superset falls back to SQLite
2. PostgreSQL plugin not reachable from Superset container
3. Database pool exhausted

**Diagnosis:**
```bash
# Check Railway logs for the actual exception
railway logs --service superset | grep -i "error\|exception\|traceback"

# Check if SQLALCHEMY_DATABASE_URI is set
railway variables --kv | grep SQLALCHEMY

# Test PostgreSQL reachability from a temporary service
railway run --service superset psql $SQLALCHEMY_DATABASE_URI -c "SELECT 1"
```

**Fix:**
1. Verify PostgreSQL plugin is provisioned in Railway
2. Set `SQLALCHEMY_DATABASE_URI` to the plugin's connection string
3. Restart Superset: `railway restart --service superset`

### Health endpoint returns 200 but UI doesn't load

**Symptom:** `/health` returns OK, but `/superset/welcome/` redirects to login and fails.

**Cause:** Likely a session/CSRF issue with the cookie.

**Fix:**
```bash
railway restart --service superset
# Clear browser cookies for the Superset domain
```

### Slow dashboard queries

**Symptom:** Dashboards take >30s to load.

**Diagnosis:**
- Check Trino query history: `http://<trino-url>/ui/query.html`
- Look for queries with `state: FAILED` or long elapsed times

**Fix:**
- Add partition filters (e.g., `election = 'GE-15'`)
- Increase Trino memory: `railway scale --service sector2-trino --memory 2GB`
- Run Iceberg compaction (see OPERATIONS.md)

## Trino

### Trino fails to start with "Catalog not found"

**Symptom:** `2026-07-30 INFO CatalogNotFoundException: Catalog 'iceberg' not found`

**Cause:** Catalog config file not mounted at `/etc/trino/catalog/iceberg.properties`

**Fix:**
1. Verify the file is in the repo at `services/trino/config/iceberg.properties`
2. Check Railway volume mount (if using one): `railway volume list`
3. Restart Trino: `railway restart --service sector2-trino`

### Iceberg queries return 403 Forbidden

**Symptom:** `SELECT * FROM iceberg.electoral.election_result` returns "Access Denied"

**Cause:** Wrong token type. R2 needs **Admin Read & Write** scope (not Object Read & Write).

**Fix:**
1. Generate new token in Cloudflare Dashboard → R2 → API tokens
2. Select **Admin Read & Write** template (not Object Read & Write)
3. Update `R2_CATALOG_TOKEN` in Railway Variables
4. Restart Trino

### ClickHouse JDBC connection fails

**Symptom:** `Connection refused: clickhouse.railway.internal:9000`

**Cause:** Trino can't reach ClickHouse plugin.

**Fix:**
1. Verify ClickHouse plugin is deployed in the same Railway project
2. Check `CLICKHOUSE_HOST` env var matches the plugin's internal DNS
3. From Trino service, test connectivity:
   ```bash
   railway run --service sector2-trino \
     curl -v telnet://$CLICKHOUSE_HOST:$CLICKHOUSE_PORT
   ```

## General

### Service keeps restarting

**Diagnosis:**
```bash
railway logs --service <name> --lines 200 | tail -50
```

Look for:
- `OOMKilled` → increase memory
- `Error: Cannot find module` → rebuild image
- `Connection refused` → check upstream dependencies

### Build fails

**Diagnosis:**
```bash
railway logs --service <name> --deployment <latest> | grep -i "fail\|error"
```

Common causes:
- Dockerfile syntax error
- Missing file (verify with `git status`)
- Base image pull failure (check Docker Hub)

## When to escalate

If the issue persists after following this guide:
1. Capture relevant logs: `railway logs --service <name> > /tmp/logs.txt`
2. Note the error message + timestamp
3. Check Railway status: https://status.railway.app
4. Contact owner / Cloudflare support as appropriate