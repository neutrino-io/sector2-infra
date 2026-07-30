#!/bin/bash
# Trino init script — wait for catalog files + start Trino
set -e

echo "======================================================================"
echo "Trino Coordinator starting"
echo "======================================================================"

# Verify catalog files exist (configured by env or volume mount)
for catalog in /etc/trino/catalog/*.properties; do
  if [ -f "$catalog" ]; then
    echo "✓ Catalog: $(basename $catalog)"
  fi
done

# Substitute env vars in catalog files (Trino doesn't auto-substitute)
echo "Substituting environment variables in catalog configs..."
for catalog in /etc/trino/catalog/*.properties; do
  if [ -f "$catalog" ]; then
    # Replace ${VAR} with value from env
    envsubst < "$catalog" > "$catalog.tmp" && mv "$catalog.tmp" "$catalog"
  fi
done

# Wait for Trino to be ready
echo "Waiting for Trino coordinator..."
until curl -sf http://localhost:8080/v1/info > /dev/null 2>&1; do
  sleep 2
done
echo "✓ Trino ready at http://localhost:8080"

# List available catalogs
echo ""
echo "Available catalogs:"
curl -sf http://localhost:8080/v1/catalog | python3 -m json.tool 2>/dev/null || echo "  (curl/python not available)"

echo "======================================================================"