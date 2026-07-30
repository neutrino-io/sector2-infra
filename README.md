# sector2-infra

Railway-deployed infrastructure for the **Sector2** political intelligence platform.

## Architecture overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          Railway Project                                       │
│                                                                              │
│  ┌────────────────┐    ┌────────────────┐    ┌─────────────────────┐        │
│  │   Superset     │───▶│  PostgreSQL    │    │   sector2-trino     │        │
│  │  (BI UI)       │    │  (metadata)    │    │  (Query engine)     │        │
│  │  port 8088     │    │                │    │  port 8080          │        │
│  └────────────────┘    └────────────────┘    └──────────┬──────────┘        │
│         │                                                 │                   │
│         │                                                 ▼                   │
│         │                                  ┌──────────────────────┐           │
│         │                                  │ Catalog: iceberg      │           │
│         │                                  │   → R2 Data Catalog    │           │
│         │                                  │ Catalog: clickhouse   │           │
│         │                                  │   → Legacy voter roll │           │
│         │                                  └──────────────────────┘           │
│         │                                                                         │
│         ▼                                                                         │
│  ┌────────────────┐                                                              │
│  │   ClickHouse   │  (legacy, Nematix-managed)                                 │
│  │   port 9000    │                                                              │
│  └────────────────┘                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
            │
            │ Iceberg REST API + Bearer token
            ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                       Cloudflare Account                                       │
│  R2 bucket (gyhc40sdz8-ivj8v3841x-bronze-storage)                             │
│  ├── Data Catalog (managed Iceberg REST)                                       │
│  │     └── Namespace: electoral → Table: election_result (53,687 rows)         │
│  └── Raw bronze envelopes                                                       │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Services

| Service | Image | Port | Purpose | Status |
|---|---|---|---|---|
| **superset** | apache/superset:latest (custom Dockerfile) | 8088 | BI dashboard UI | ✅ Live |
| **sector2-trino** | trinodb/trino:435 | 8080 | SQL query engine | ❌ Not deployed |
| **postgresql** (plugin) | Railway-managed | 5432 | Superset metadata | ✅ Live |
| **redis** (plugin) | Railway-managed | 6379 | Cache + rate limit (optional) | ⚠️ Optional |
| **clickhouse** | (legacy, Nematix-managed) | 9000 | Historical voter roll | ✅ Live |

## Directory layout

```
sector2-infra/
├── README.md                       # This file
├── CLAUDE.md                       # AI-context for future agents
├── railway.toml                    # Multi-service deployment config
├── .env.example                    # Template for required env vars
├── .gitignore                      # Python __pycache__, etc.
│
├── services/
│   ├── superset/                   # Apache Superset service
│   ├── trino/                      # Trino query engine (NEW)
│   └── clickhouse/                 # ClickHouse skeleton (NOT deployed)
│
├── shared/
│   ├── docs/                       # ARCHITECTURE, DEPLOYMENT, OPERATIONS, etc.
│   ├── secrets/                    # Secrets management guide
│   └── tools/                      # Verification + maintenance scripts
│
└── tests/                          # Smoke tests for each service
```

## Data flow

```
Cloudflare R2 (Iceberg REST)
    │
    │ HTTPS + Bearer token
    ▼
Trino (sector2-trino service)
    │ Catalog: iceberg → R2 Iceberg tables
    │ Catalog: clickhouse → legacy voter roll
    │
    │ SQL via JDBC (port 8080)
    ▼
Superset (apache/superset)
    │ Database: trino://sector2-trino:8080/iceberg/electoral
    │
    │ HTTP + JWT
    ▼
Browser dashboards
```

## First-time deployment

See `shared/docs/DEPLOYMENT.md`.

## Daily operations

See `shared/docs/OPERATIONS.md`.

## Troubleshooting

See `shared/docs/TROUBLESHOOTING.md`.

## Migration history

This repo consolidates infrastructure previously split across:
- `/DATA/Development/Sector2/Sources/apache-superset-railway/` (Superset-only, archived after refactor)
- `/DATA/Development/Sector2/Sources/sector2-core/superset/` (local dev docker-compose, kept for CI)

The original `apache-superset-railway` repo remains accessible for rollback during the transition period.