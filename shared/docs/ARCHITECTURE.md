# Architecture

## System overview

`sector2-infra` deploys the BI tier of the Sector2 platform on Railway:

- **Superset** — BI dashboard UI
- **Trino** — distributed SQL query engine
- **ClickHouse** — historical voter roll (legacy, Nematix-managed)
- **PostgreSQL** — Superset metadata DB (Railway plugin)
- **Redis** — cache + rate limiting (Railway plugin, optional)

The **data layer** lives outside this repo:
- **R2 (Cloudflare)** — bronze envelopes + Iceberg Data Catalog
- **D1 (Cloudflare)** — serving marts for the Workers API
- **Workers (Cloudflare)** — API surface

## Data flow

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          Cloudflare                                           │
│                                                                              │
│  Workers API ──────────► D1 marts (serving layer)                           │
│       │                                                                      │
│       └──────────► R2 Data Catalog (Iceberg REST) ──┐                         │
│                                                   │                         │
│  Pipelines (Phase 2) ───► R2 bronze envelopes ──┐ │                         │
└─────────────────────────────────────────────────┼─┼─────────────────────────┘
                                                  │ │
                       Iceberg REST API + Bearer   │ │
                                                  ▼ ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                          Railway                                              │
│                                                                              │
│  Trino ──── JDBC ────► Superset ──── JWT ────► Browser                       │
│    │                                       ▲                                │
│    └────► ClickHouse (legacy voter roll) ───┘                                │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Service dependencies

```
Trino ──reads──► R2 Data Catalog (Iceberg)
Trino ──reads──► ClickHouse (JDBC)
Superset ──reads──► Trino (JDBC) — Phase 2
Superset ──reads──► ClickHouse (direct, current)
Superset ──reads/writes──► PostgreSQL (metadata)
Superset ──reads/writes──► Redis (cache)
```

## Network topology

All services run on Railway's internal network. Cross-service communication via:

- `*.railway.internal` DNS (private)
- Public ingress only on Superset (`apache-superset-railway-production-13fe.up.railway.app`)
- Trino stays internal (only Superset connects to it)

## Why this architecture

1. **Single source of truth**: Iceberg REST catalog on R2 is the canonical data store
2. **Stateless query layer**: Trino scales horizontally; no data lives in it
3. **Tiered storage**:
   - Bronze (R2 raw) → Gold (R2 Iceberg) → Marts (D1, Workers API)
   - BI tier reads from Iceberg; API tier reads from D1
4. **Service isolation**: each service has its own Dockerfile, env, secrets

## Anti-patterns avoided

- ❌ **Multiple sibling repos** for each service (operational friction)
- ❌ **R2 SQL as BI backend** (no JOINs, no CTEs — limited analytics)
- ❌ **ClickHouse as the only DB** (no Iceberg, no ACID on writes)
- ❌ **Trino writing back to source** (read-only by design)
- ❌ **Hardcoded secrets in repo** (Railway Variables only)

## Future evolution

| Trigger | Action |
|---|---|
| Trino > 1M queries/day | Split coordinator + worker services |
| Iceberg tables > 100 GB | Add compaction job (Worker cron → R2 SQL `OPTIMIZE`) |
| Multi-tenant Superset users | Add Apache Ranger for row-level access control |
| ClickHouse becomes bottleneck | Migrate voter roll to Iceberg tables |
| > 3 services need shared infra | Extract common modules to `shared/python/` |