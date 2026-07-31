#!/bin/bash
# run-trino.sh - Substitutes env vars in catalog configs, then launches Trino.

set -e

# Write to file AND stdout (Railway might filter stdout)
LOG="/tmp/trino-startup.log"

exec > >(tee -a "$LOG") 2>&1

echo "=== Trino startup script running at $(date -u) ==="

CONFIG_DIR="/tmp/trino-catalog"
mkdir -p "$CONFIG_DIR/catalog"

echo "Config dir: $CONFIG_DIR"
echo "R2_ICEBERG_REST_URI: ${R2_ICEBERG_REST_URI:+SET (len=${#R2_ICEBERG_REST_URI})}"
echo "R2_CATALOG_TOKEN: ${R2_CATALOG_TOKEN:+SET (len=${#R2_CATALOG_TOKEN})}"
echo "R2_S3_ENDPOINT: ${R2_S3_ENDPOINT:+SET (len=${#R2_S3_ENDPOINT})}"
echo "R2_ACCESS_KEY: ${R2_ACCESS_KEY:+SET}"

# Copy catalog configs
cp /etc/trino/catalog/*.properties "$CONFIG_DIR/catalog/"

# Substitute placeholders
for f in "$CONFIG_DIR/catalog"/*.properties; do
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
    echo "--- Substituted content (non-secret) ---"
    grep -v "SECRET\|PASSWORD\|KEY" "$f" || echo "(all values hidden)"
done

echo "=== Launching Trino with --etc-dir $CONFIG_DIR ==="
exec /usr/lib/trino/bin/launcher run --etc-dir "$CONFIG_DIR"
