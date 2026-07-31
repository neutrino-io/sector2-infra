#!/bin/bash
# Run Trino with substituted catalog configs
# This script is set as the startCommand so Railway runs it instead
# of the base image's launcher directly

set -e

# Copy catalogs to a writable dir
mkdir -p /tmp/trino-configs
cp /etc/trino/catalog/*.properties /tmp/trino-configs/

# Substitute placeholders with env vars
for f in /tmp/trino-configs/*.properties; do
  if [ -f "$f" ]; then
    sed -i \
      -e "s|__R2_ICEBERG_REST_URI__|${R2_ICEBERG_REST_URI:-}|g" \
      -e "s|__R2_CATALOG_WAREHOUSE__|${R2_ICEBERG_WAREHOUSE:-}|g" \
      -e "s|__R2_CATALOG_TOKEN__|${R2_CATALOG_TOKEN:-}|g" \
      -e "s|__R2_ACCESS_KEY__|${R2_ACCESS_KEY:-}|g" \
      -e "s|__R2_SECRET_KEY__|${R2_SECRET_KEY:-}|g" \
      -e "s|__R2_S3_ENDPOINT__|${R2_S3_ENDPOINT:-}|g" \
      -e "s|__CLICKHOUSE_HOST__|${CLICKHOUSE_HOST:-clickhouse}|g" \
      -e "s|__CLICKHOUSE_PORT__|${CLICKHOUSE_PORT:-9000}|g" \
      -e "s|__CLICKHOUSE_USER__|${CLICKHOUSE_USER:-default}|g" \
      -e "s|__CLICKHOUSE_PASSWORD__|${CLICKHOUSE_PASSWORD:-}|g" \
      "$f"
  fi
done

# Run Trino launcher with the substituted config dir
exec /usr/lib/trino/bin/launcher run --catalog-config-dir /tmp/trino-configs
