#!/bin/bash
# Add Trino (Iceberg REST) database to the live Superset.
# Run AFTER Trino service is deployed on Railway.
#
# Prerequisites:
#   1. sector2-trino deployed on Railway (verify with `railway status`)
#   2. SUPERSET_ADMIN_USER + SUPERSET_ADMIN_PASS env vars set
#   3. Network access from this machine to Superset public URL
#
# What it does:
#   1. Login to Superset (get JWT)
#   2. POST /api/v1/database/ with Trino SQLAlchemy URI
#   3. Verify connection via /api/v1/database/{id}/connection/
#   4. Print next steps (add datasets, build dashboards)
set -e

SUPERSET_URL=${SUPERSET_URL:-https://sector2-superset-production.up.railway.app}
TRINO_HOST=${TRINO_HOST:-sector2-trino.railway.internal}
TRINO_PORT=${TRINO_PORT:-8080}
TRINO_USER=${SUPERSET_ADMIN_USER:-admin}
TRINO_PASS=${SUPERSET_ADMIN_PASS:-admin}

# 1. Login
echo "Logging in to $SUPERSET_URL..."
JWT=$(curl -sS -X POST "$SUPERSET_URL/api/v1/security/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$TRINO_USER\",\"password\":\"$TRINO_PASS\",\"provider\":\"db\"}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")
if [ -z "$JWT" ]; then
  echo "ERROR: Login failed"
  exit 1
fi
echo "✓ Got JWT"

# 2. Check if database already exists
echo ""
echo "Checking existing databases..."
EXISTING=$(curl -sS "$SUPERSET_URL/api/v1/database/" \
  -H "Authorization: Bearer $JWT" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); names=[x['database_name'] for x in d['result']]; print(','.join([n for n in names if 'trino' in n.lower() or 'iceberg' in n.lower()]))" 2>&1)

if [ -n "$EXISTING" ]; then
  echo "✓ Trino/Iceberg database already exists: $EXISTING"
  exit 0
fi

# 3. Add Trino database
echo ""
echo "Adding Trino database to Superset..."
SQLALCHEMY_URI="trino://${TRINO_HOST}:${TRINO_PORT}/iceberg/electoral"

RESP=$(curl -sS -X POST "$SUPERSET_URL/api/v1/database/" \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d "{
    \"database_name\": \"Trino Iceberg (R2)\",
    \"sqlalchemy_uri\": \"$SQLALCHEMY_URI\",
    \"expose_in_sqllab\": true,
    \"allow_ctas\": false,
    \"allow_cvas\": false,
    \"allow_dml\": false,
    \"allow_file_upload\": false,
    \"allow_run_async\": true
  }")
DB_ID=$(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id') or d.get('result',{}).get('id') or '')" 2>&1)
echo "✓ Database added: id=$DB_ID"

# 4. Test connection
echo ""
echo "Testing connection..."
RESULT=$(curl -sS "$SUPERSET_URL/api/v1/database/$DB_ID/connection/" \
  -H "Authorization: Bearer $JWT" 2>&1)
echo "  Result: $RESULT" | head -3

# 5. List available datasets
echo ""
echo "Datasets now available:"
curl -sS "$SUPERSET_URL/api/v1/dataset/?q=(database_id:$DB_ID)" \
  -H "Authorization: Bearer $JWT" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'  Count: {d[\"count\"]}'); [print(f'    - {x[\"table_name\"]}') for x in d['result']]" 2>&1

echo ""
echo "======================================================================"
echo "✓ Trino Iceberg database added to Superset"
echo "  ID: $DB_ID"
echo "  URL: $SUPERSET_URL/database/list/"
echo ""
echo "Next steps:"
echo "  1. Open Superset UI"
echo "  2. Data → Datasets → 'Trino Iceberg (R2)' → add columns"
echo "  3. Build a chart on electoral.election_result"
echo "  4. Save as dashboard 'GE-15 Election Results Explorer'"
echo "======================================================================"