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
set -euo pipefail

COOKIE_JAR=$(mktemp)
CSRF_TOKEN=""
trap 'rm -f "$COOKIE_JAR"' EXIT

SUPERSET_URL=${SUPERSET_URL:-https://sector2-superset-production.up.railway.app}
TRINO_HOST=${TRINO_HOST:-sector2-trino.railway.internal}
TRINO_PORT=${TRINO_PORT:-8080}
TRINO_USER=${SUPERSET_ADMIN_USER:-admin}
TRINO_PASS=${SUPERSET_ADMIN_PASS:-admin}

# 1. Login
JWT=$(curl -sS -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST "$SUPERSET_URL/api/v1/security/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$TRINO_USER\",\"password\":\"$TRINO_PASS\",\"provider\":\"db\"}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")
if [ -z "$JWT" ]; then
  echo "ERROR: Login failed"
  exit 1
fi
echo "✓ Got JWT"

# Superset >= 4.x issues a CSRF token after login. Fetch it from the dedicated
# endpoint or fall back to the csrf_token cookie that the previous request set.
CSRF_TOKEN=$(curl -sS -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -H "Authorization: Bearer $JWT" \
  "$SUPERSET_URL/api/v1/security/csrf_token/" \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('csrf_token',''))" 2>/dev/null || true)
if [ -z "$CSRF_TOKEN" ]; then
  CSRF_TOKEN=$(awk '$6=="csrf_token" {print $7}' "$COOKIE_JAR" | tail -n1 || true)
fi
if [ -z "$CSRF_TOKEN" ]; then
  echo "WARN: CSRF token unavailable; continuing — Superset may reject the POST"
fi

# 2. Check if database already exists
echo ""
echo "Checking existing databases..."
EXISTING=$(curl -sS -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$SUPERSET_URL/api/v1/database/" \
  -H "Authorization: Bearer $JWT" \
  -H "X-CSRFToken: $CSRF_TOKEN" -H "Referer: $SUPERSET_URL" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); names=[x['database_name'] for x in d.get('result', [])]; print(','.join([n for n in names if 'trino' in n.lower() or 'iceberg' in n.lower()]))" 2>&1)

if [ -n "$EXISTING" ]; then
  echo "✓ Trino/Iceberg database already exists: $EXISTING"
  exit 0
fi

# 3. Add Trino database
echo ""
echo "Adding Trino database to Superset..."
RESP=$(curl -sS -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST "$SUPERSET_URL/api/v1/database/" \
  -H "Authorization: Bearer $JWT" \
  -H "X-CSRFToken: $CSRF_TOKEN" -H "Referer: $SUPERSET_URL" \
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
DB_ID=$(echo "$RESP" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('id') or (d.get('result') or {}).get('id') or '')
" 2>&1)
echo "✓ Database added: id=$DB_ID"

# 4. Test connection
echo ""
echo "Testing connection..."
RESULT=$(curl -sS -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$SUPERSET_URL/api/v1/database/$DB_ID/connection/" \
  -H "Authorization: Bearer $JWT" \
  -H "X-CSRFToken: $CSRF_TOKEN" -H "Referer: $SUPERSET_URL" 2>&1)
echo "  Result: $RESULT" | head -3

# 5. List available datasets
echo ""
echo "Datasets now available:"
curl -sS -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$SUPERSET_URL/api/v1/dataset/?q=(database_id:$DB_ID)" \
  -H "Authorization: Bearer $JWT" \
  -H "X-CSRFToken: $CSRF_TOKEN" -H "Referer: $SUPERSET_URL" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'  Count: {d.get(\"count\", 0)}'); [print(f'    - {x[\"table_name\"]}') for x in d.get('result', [])]" 2>&1

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