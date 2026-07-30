#!/bin/bash
# Trino startup script — verifies configs before launching
set -e

echo "======================================================================"
echo "Trino Coordinator starting"
echo "======================================================================"

# List catalog configs
echo "Catalog configs in /etc/trino/catalog/:"
ls -la /etc/trino/catalog/
echo ""

# Substitute env vars in catalog files (Trino's launcher does NOT do this)
echo "Substituting environment variables in catalog configs..."
for catalog in /etc/trino/catalog/*.properties; do
  if [ -f "$catalog" ]; then
    echo "  Processing: $(basename $catalog)"
    envsubst < "$catalog" > "$catalog.tmp" && mv "$catalog.tmp" "$catalog"
    chown trino:trino "$catalog"
  fi
done

echo ""
echo "Waiting for Trino to be ready..."
until curl -sf http://localhost:8080/v1/info > /dev/null 2>&1; do
  sleep 2
done
echo "✓ Trino ready at http://localhost:8080"

echo ""
echo "Available catalogs:"
curl -sf http://localhost:8080/v1/catalog 2>/dev/null | python3 -c "
import json, sys
try:
    cats = json.load(sys.stdin)
    [print(f'  - {c}') for c in cats]
except Exception:
    print('  (catalog query failed — check logs)')
" 2>/dev/null || echo "  (python3 not available)"

echo "======================================================================"
