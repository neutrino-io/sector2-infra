#!/bin/bash
# Minimal init script
set -e

# Create a marker file (proves the script ran)
echo "Trino init at $(date -u)" > /tmp/trino-ran.txt
echo "Process ID: $$" >> /tmp/trino-ran.txt
echo "User: $(whoami)" >> /tmp/trino-ran.txt
echo "Args: $@" >> /tmp/trino-ran.txt
echo "Env vars:" >> /tmp/trino-ran.txt
env | grep -E "R2_|CLICKHOUSE_" >> /tmp/trino-ran.txt

# Make it readable from outside
chmod 644 /tmp/trino-ran.txt

# Substitute placeholders in catalog configs
for catalog in /etc/trino/catalog/*.properties; do
  if [ -f "$catalog" ]; then
    echo "  Substituting: $(basename $catalog)"
    sed -i \
      -e "s|__R2_ICEBERG_REST_URI__|${R2_ICEBERG_REST_URI:-}|g" \
      -e "s|__R2_CATALOG_TOKEN__|${R2_CATALOG_TOKEN:-}|g" \
      -e "s|__R2_ACCESS_KEY__|${R2_ACCESS_KEY:-}|g" \
      -e "s|__R2_SECRET_KEY__|${R2_SECRET_KEY:-}|g" \
      -e "s|__R2_S3_ENDPOINT__|${R2_S3_ENDPOINT:-}|g" \
      -e "s|__CLICKHOUSE_HOST__|${CLICKHOUSE_HOST:-clickhouse}|g" \
      -e "s|__CLICKHOUSE_PORT__|${CLICKHOUSE_PORT:-9000}|g" \
      -e "s|__CLICKHOUSE_USER__|${CLICKHOUSE_USER:-default}|g" \
      -e "s|__CLICKHOUSE_PASSWORD__|${CLICKHOUSE_PASSWORD:-}|g" \
      "$catalog"
  fi
done

chown -R trino:trino /etc/trino/catalog/

# Run Trino
exec /usr/lib/trino/bin/launcher run
