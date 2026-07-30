#!/bin/bash
# Helper: rotate R2 tokens across all services
# Usage:
#   R2_NEW_TOKEN=cfat_NEWVALUE ./update-tokens.sh
#
# What it does:
# 1. Updates R2_CATALOG_TOKEN in Railway Variables
# 2. Restarts all services that reference the token
# 3. Verifies token works (via Trino SELECT 1 against Iceberg)
set -e

if [ -z "$R2_NEW_TOKEN" ]; then
  echo "ERROR: Set R2_NEW_TOKEN env var to the new token value"
  exit 1
fi

# Services that need the new token
SERVICES="superset sector2-trino"

echo "Updating R2_CATALOG_TOKEN..."
railway variables --set R2_CATALOG_TOKEN="$R2_NEW_TOKEN"

echo ""
echo "Restarting services: $SERVICES"
for svc in $SERVICES; do
  echo "  Restarting $svc..."
  railway restart --service "$svc"
done

echo ""
echo "Waiting 30s for services to come back up..."
sleep 30

echo ""
echo "Verifying token works..."
TRINO_URL=${TRINO_URL:-http://localhost:8080}
RESULT=$(curl -sf -X POST "$TRINO_URL/v1/statement" \
  -H 'Content-Type: application/json' \
  -H 'X-Trino-User: verify' \
  -d '{"query":"SELECT COUNT(*) FROM iceberg.electoral.election_result"}' 2>&1)
echo "  Result: $RESULT"

if echo "$RESULT" | grep -q "53,687\|53687"; then
  echo ""
  echo "✓ Token rotation successful"
else
  echo ""
  echo "✗ Token rotation failed — verify manually"
  exit 1
fi