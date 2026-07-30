# sector2-infra tests

Smoke tests for each service. Run after deploying.

## Quick start

```bash
# Run all tests
./shared/tools/verify-all.sh

# Run individual service tests
./services/trino/verify-iceberg.sh

# PyIceberg direct (no Trino needed)
python3 tests/test-iceberg-connection.py
```

## Tests

| File | Service | What it tests |
|---|---|---|
| `test-iceberg-connection.py` | PyIceberg → R2 | Direct catalog access (validates R2 token) |
| `test-trino-queries.sh` | Trino → Iceberg | Trino can list catalogs + query tables |
| `verify-all.sh` (shared) | All | Comprehensive smoke test |

## Adding new tests

1. Create `tests/test-<name>.sh` or `.py`
2. Use `set -e` to fail fast
3. Print clear pass/fail output
4. Reference `../services/<service>/` for source files

## CI integration

Tests run on every push via GitHub Actions (when CI is enabled).
Currently CI is **disabled** — see `docs/plans/2026-07-30-sector2-infra-refactor-proposal.md`.

## Local dev tests

Some tests require live Railway services. For local-only tests:

```bash
# Local docker-compose (sector2-core/superset/docker-compose.yml)
cd /DATA/Development/Sector2/Sources/sector2-core
docker compose -f superset/docker-compose.yml up
# Tests against localhost:8080 (Trino) + localhost:8088 (Superset)