#!/bin/bash
# Trino startup — substitute env vars into catalog configs before launching
set -e

echo "======================================================================"
echo "Trino Coordinator starting"
echo "======================================================================"

# Substitute placeholders in catalog configs with env vars
for catalog in /etc/trino/catalog/*.properties; do
  if [ -f "$catalog" ]; then
    echo "  Substituting: $(basename $catalog)"
    sed -i \
      -e "s|__R2_ICEBERG_REST_URI__|${R2_ICEBERG_REST_URI:-}|g" \
      -e "s|__R2_CATALOG_TOKEN__|${R2_CATALOG_TOKEN:-}|g" \
      -e "s|__R2_S3_ENDPOINT__|${R2_S3_ENDPOINT:-}|g" \
      -e "s|__R2_ACCESS_KEY__|${R2_ACCESS_KEY:-}|g" \
      -e "s|__R2_SECRET_KEY__|${R2_SECRET_KEY:-}|g" \
      -e "s|__CLICKHOUSE_HOST__|${CLICKHOUSE_HOST:-clickhouse}|g" \
      -e "s|__CLICKHOUSE_PORT__|${CLICKHOUSE_PORT:-9000}|g" \
      -e "s|__CLICKHOUSE_USER__|${CLICKHOUSE_USER:-default}|g" \
      -e "s|__CLICKHOUSE_PASSWORD__|${CLICKHOUSE_PASSWORD:-}|g" \
      "$catalog"
  fi
done

# Fix ownership (configs may be root-owned if COPY was used)
chown -R trino:trino /etc/trino/catalog/

echo ""
echo "Catalog configs ready. Starting Trino..."
exec /etc/trino/bin/run-trino
