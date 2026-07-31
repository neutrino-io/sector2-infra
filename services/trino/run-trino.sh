#!/bin/bash
# run-trino.sh - Substitutes env vars in catalog configs, then launches Trino.
# This runs instead of the default CMD so we can use Railway Variables for secrets.

set -e

CONFIG_DIR="/tmp/trino-catalog"
mkdir -p "$CONFIG_DIR"

echo "=== Trino startup: substituting env vars in catalog configs ==="

# Copy all catalog configs to writable dir
cp /etc/trino/catalog/*.properties "$CONFIG_DIR/"

# Substitute each placeholder with the corresponding env var
for f in "$CONFIG_DIR"/*.properties; do
    echo "Processing: $f"
    sed -i \
        -e "s|__R2_ICEBERG_REST_URI__|${R2_ICEBERG_REST_URI:-}|g" \
        -e "s|__R2_ICEBERG_WAREHOUSE__|${R2_ICEBERG_WAREHOUSE:-}|g" \
        -e "s|__R2_CATALOG_TOKEN__|${R2_CATALOG_TOKEN:-}|g" \
        -e "s|__R2_ACCESS_KEY__|${R2_ACCESS_KEY:-}|g" \
        -e "s|__R2_SECRET_KEY__|${R2_SECRET_KEY:-}|g" \
        -e "s|__R2_S3_ENDPOINT__|${R2_S3_ENDPOINT:-}|g" \
        -e "s|__CLICKHOUSE_HOST__|${CLICKHOUSE_HOST:-}|g" \
        -e "s|__CLICKHOUSE_PORT__|${CLICKHOUSE_PORT:-}|g" \
        -e "s|__CLICKHOUSE_USER__|${CLICKHOUSE_USER:-}|g" \
        -e "s|__CLICKHOUSE_PASSWORD__|${CLICKHOUSE_PASSWORD:-}|g" \
        "$f"
    echo "--- $f ---"
    cat "$f"
    echo ""
done

echo "=== Launching Trino with --etc-dir $CONFIG_DIR ==="
exec /usr/lib/trino/bin/launcher run --etc-dir "$CONFIG_DIR"
