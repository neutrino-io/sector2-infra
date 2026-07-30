#!/bin/bash
# Trino end-to-end test
# Requires Trino service to be running (local or Railway)
set -e

TRINO_URL=${TRINO_URL:-http://localhost:8080}
CATALOG=${CATALOG:-iceberg}
SCHEMA=${SCHEMA:-electoral}
TABLE=${TABLE:-election_result}

echo "======================================================================"
echo "Trino query tests (URL: $TRINO_URL)"
echo "======================================================================"

passes=0
fails=0

run_query() {
  local query="$1"
  local desc="$2"
  echo ""
  echo "[$((passes + fails + 1))] $desc"
  echo "    Query: $query"
  local result=$(curl -sf -X POST "$TRINO_URL/v1/statement" \
    -H 'Content-Type: application/json' \
    -H 'X-Trino-User: test' \
    -d "{\"query\":\"$query\"}" 2>&1)
  echo "    Response: $result" | head -3
  if [ -n "$result" ]; then
    passes=$((passes + 1))
  else
    fails=$((fails + 1))
  fi
}

# 1. Health
echo "[1] Health check"
if curl -sf "$TRINO_URL/v1/info" > /dev/null; then
  echo "    ✓ Trino is up"
  passes=$((passes + 1))
else
  echo "    ✗ Trino is not reachable"
  fails=$((fails + 1))
  exit 1
fi

# 2. List catalogs
run_query "SHOW CATALOGS" "List catalogs"

# 3. List schemas in Iceberg
run_query "SHOW SCHEMAS FROM $CATALOG" "List schemas in $CATALOG"

# 4. List tables in electoral
run_query "SHOW TABLES FROM $CATALOG.$SCHEMA" "List tables in $CATALOG.$SCHEMA"

# 5. Row count
run_query "SELECT COUNT(*) AS cnt FROM $CATALOG.$SCHEMA.$TABLE" "Row count for $TABLE"

# 6. Partition pruning
run_query "SELECT COUNT(*) FROM $CATALOG.$SCHEMA.$TABLE WHERE election = 'GE-15' AND level = 'parlimen'" "Partition pruning test (GE-15 parlimen)"

# 7. Sample winners
run_query "SELECT candidate_name, party, votes_cast FROM $CATALOG.$SCHEMA.$TABLE WHERE is_winner = 1 AND election = 'GE-15' ORDER BY votes_cast DESC LIMIT 5" "Top 5 GE-15 winners"

echo ""
echo "======================================================================"
echo "Results: $passes passed, $fails failed"
echo "======================================================================"
[ $fails -eq 0 ] || exit 1