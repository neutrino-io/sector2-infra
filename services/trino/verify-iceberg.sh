#!/bin/bash
# Verify Trino can query Iceberg REST catalog
# Usage: ./verify-iceberg.sh
# Requires: curl, python3
set -e

TRINO_URL=${TRINO_URL:-http://localhost:8080}
CATALOG=${CATALOG:-iceberg}
SCHEMA=${SCHEMA:-electoral}
TABLE=${TABLE:-election_result}

echo "======================================================================"
echo "Trino Iceberg verification"
echo "======================================================================"
echo "Trino:     $TRINO_URL"
echo "Catalog:   $CATALOG"
echo "Schema:    $SCHEMA"
echo "Table:     $TABLE"
echo ""

# 1. Verify Trino is up
echo "[1] Health check..."
RESP=$(curl -sf "$TRINO_URL/v1/info" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'OK (version={d.get(\"nodeVersion\",{}).get(\"version\",\"?\")})')" 2>&1)
echo "    ✓ $RESP"

# 2. List catalogs
echo ""
echo "[2] Catalogs..."
curl -sf "$TRINO_URL/v1/catalog" | python3 -c "import json,sys; cats = json.load(sys.stdin); [print(f'    - {c}') for c in cats]"

# 3. List schemas in Iceberg
echo ""
echo "[3] Schemas in $CATALOG..."
curl -sf "$TRINO_URL/v1/catalog/$CATALOG/schemas" | python3 -c "import json,sys; d=json.load(sys.stdin); [print(f'    - {s[\"schema\"]}') for s in d if 'schema' in s]"

# 4. List tables in electoral
echo ""
echo "[4] Tables in $CATALOG.$SCHEMA..."
curl -sf "$TRINO_URL/v1/catalog/$CATALOG/schemas/$SCHEMA/tables" | python3 -c "import json,sys; d=json.load(sys.stdin); [print(f'    - {t[\"name\"]}') for t in d if 'name' in t]"

# 5. Row count
echo ""
echo "[5] Row count: SELECT COUNT(*) FROM $CATALOG.$SCHEMA.$TABLE"
RESULT=$(curl -sf -X POST "$TRINO_URL/v1/statement" \
  -H 'Content-Type: application/json' \
  -H 'X-Trino-User: verify' \
  -d "{\"query\":\"SELECT COUNT(*) AS cnt FROM $CATALOG.$SCHEMA.$TABLE\"}" 2>&1)
echo "    $RESULT"

echo ""
echo "======================================================================"
echo "All checks complete"
echo "======================================================================"