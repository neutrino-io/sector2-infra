#!/bin/bash
# This is the actual ENTRYPOINT
set -e

echo "=== ENTRYPOINT STARTED ===" | tee /tmp/entry.log
echo "R2_S3_ENDPOINT=${R2_S3_ENDPOINT:-UNSET}" >> /tmp/entry.log

# Copy configs to /tmp/trino-etc/catalog
mkdir -p /tmp/trino-etc/catalog
cp /etc/trino/catalog/*.properties /tmp/trino-etc/catalog/

# Substitute
for f in /tmp/trino-etc/catalog/*.properties; do
    sed -i \
        -e "s|__R2_ICEBERG_REST_URI__|${R2_ICEBERG_REST_URI:-}|g" \
        -e "s|__R2_ICEBERG_WAREHOUSE__|${R2_ICEBERG_WAREHOUSE:-}|g" \
        -e "s|__R2_CATALOG_TOKEN__|${R2_CATALOG_TOKEN:-}|g" \
        -e "s|__R2_ACCESS_KEY__|${R2_ACCESS_KEY:-}|g" \
        -e "s|__R2_SECRET_KEY__|${R2_SECRET_KEY:-}|g" \
        -e "s|__R2_S3_ENDPOINT__|${R2_S3_ENDPOINT:-}|g" \
        "$f"
done

echo "=== ENTRYPOINT: Launching Trino ===" >> /tmp/entry.log
exec /usr/lib/trino/bin/launcher run --etc-dir /tmp/trino-etc
