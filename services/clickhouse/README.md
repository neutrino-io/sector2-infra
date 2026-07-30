# ClickHouse (skeleton — not deployed)

This service is **a skeleton only**. The actual ClickHouse instance is managed by the
Nematix account on Railway (separate service, separate `gyhc40sdz8-ivj8v3841x-*` namespace).

## Why skeleton?

The `sector2-infra` refactor consolidates infrastructure config but does NOT migrate the
existing ClickHouse instance. Reasons:

1. **Data gravity**: voter roll (1,048,540 PII rows) lives in the current ClickHouse; migrating is non-trivial
2. **Owner decision**: any PII migration requires owner sign-off
3. **Read-only access**: existing Trino config connects to ClickHouse as read-only consumer; no need to redeploy

## Files

- `Dockerfile.disabled` — template only, not built
- `schema.ddl.example` — would create the `sector2` schema with voter roll tables
- `config.xml.example` — would configure network/auth

## How to activate (if ever needed)

```bash
# 1. Rename Dockerfile.disabled to Dockerfile
mv Dockerfile.disabled Dockerfile

# 2. Add to root railway.toml
cat >> ../../railway.toml <<EOF

[[services]]
name = "clickhouse"
dockerfilePath = "services/clickhouse/Dockerfile"
[services.deploy]
startCommand = "/entrypoint.sh"
healthcheckPath = "/ping"
EOF

# 3. Set Railway env vars:
#    CLICKHOUSE_USER, CLICKHOUSE_PASSWORD

# 4. Migrate data (out of scope for this refactor)
```

## Current state (2026-07-30)

- ✅ ClickHouse instance live on Railway (separate service)
- ✅ 6 datasets configured in Superset (`election_pahang`, `district`, `vd_voters_enriched`, etc.)
- ✅ Trino `clickhouse.properties` config ready to connect once Trino is deployed
- ❌ This skeleton directory NOT deployed