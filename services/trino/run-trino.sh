#!/bin/bash
# run-trino.sh - Substitutes env vars in catalog configs, then launches Trino.
# This runs as ENTRYPOINT so Railway Variables can be injected at runtime.

set -e

# Trino's --etc-dir replaces the "etc/" prefix, so catalogs go at $DIR/catalog/
CONFIG_DIR="/tmp/trino-catalog"
mkdir -p "$CONFIG_DIR/catalog"

echo "=== Trino startup: substituting env vars in catalog configs ==="
echo "Config dir: $CONFIG_DIR"
echo "Env vars: R2_ICEBERG_REST_URI=${R2_ICEBERG_REST_URI:+SET} R2_CATALOG_TOKEN=${R2_CATALOG_TOKEN:+SET} R2_S3_ENDPOINT=${R2_S3_ENDPOINT:+SET}"

# Copy catalog configs to writable dir (with catalog/ subdir)
cp /etc/trino/catalog/*.properties "$CONFIG_DIR/catalog/"

# Substitute placeholders with Railway env vars
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
    echo "--- $f ---"
    grep -v "SECRET\|PASSWORD\|KEY" "$f" || true
done

echo "=== Launching Trino with --etc-dir $CONFIG_DIR ==="
exec /usr/lib/trino/bin/launcher run --etc-dir "$CONFIG_DIR"
