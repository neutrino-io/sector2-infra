#!/bin/bash
# Full smoke test for sector2-infra services
# Run after deploying all services
set -e

SUPERSET_URL=${SUPERSET_URL:-http://localhost:8088}
TRINO_URL=${TRINO_URL:-http://localhost:8080}
CLICKHOUSE_URL=${CLICKHOUSE_URL:-http://localhost:9000}

echo "======================================================================"
echo "sector2-infra smoke test"
echo "======================================================================"
echo "Superset:    $SUPERSET_URL"
echo "Trino:       $TRINO_URL"
echo "ClickHouse:  $CLICKHOUSE_URL"
echo ""

pass=0
fail=0

check() {
  local name="$1"
  local cmd="$2"
  if eval "$cmd" > /dev/null 2>&1; then
    echo "  ✓ $name"
    pass=$((pass + 1))
  else
    echo "  ✗ $name"
    fail=$((fail + 1))
  fi
}

# Superset
echo "Superset:"
check "Health endpoint" "curl -sf $SUPERSET_URL/health"
check "Login page renders" "curl -sf $SUPERSET_URL/login/ -o /dev/null"
check "MCP endpoint" "curl -X POST $SUPERSET_URL/mcp -o /dev/null"
echo ""

# Trino
echo "Trino:"
check "Health endpoint" "curl -sf $TRINO_URL/v1/info"
check "List catalogs" "curl -sf $TRINO_URL/v1/catalog"
check "List Iceberg schemas" "curl -sf $TRINO_URL/v1/catalog/iceberg/schemas"
check "List electoral tables" "curl -sf $TRINO_URL/v1/catalog/iceberg/schemas/electoral/tables"
echo ""

# ClickHouse
echo "ClickHouse (optional):"
check "Native TCP connect" "timeout 3 bash -c \"cat < /dev/tcp/$(echo $CLICKHOUSE_URL | sed 's|http://||; s|:.*||')/$(echo $CLICKHOUSE_URL | sed 's|.*:||')\" < /dev/null 2>&1"
echo ""

echo "======================================================================"
echo "Results: $pass passed, $fail failed"
echo "======================================================================"
[ $fail -eq 0 ] || exit 1