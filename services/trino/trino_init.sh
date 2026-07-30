#!/bin/bash
# Trino startup — substitute env vars into catalog configs before launching
set -e

LOG=/tmp/trino_init.log
echo "======================================================================"  | tee $LOG
echo "Trino Coordinator starting at $(date -u)" | tee -a $LOG
echo "======================================================================"  | tee -a $LOG

# Log env vars
echo "Env vars available:" | tee -a $LOG
for var in R2_ICEBERG_REST_URI R2_CATALOG_TOKEN R2_ACCESS_KEY R2_SECRET_KEY R2_S3_ENDPOINT; do
  val=$(eval "echo \$$var")
  if [ -n "$val" ]; then
    echo "  $var is set (length: ${#val})" | tee -a $LOG
  else
    echo "  $var is EMPTY" | tee -a $LOG
  fi
done

# Log catalog configs BEFORE substitution
echo "" | tee -a $LOG
echo "Catalog configs BEFORE substitution:" | tee -a $LOG
for f in /etc/trino/catalog/*.properties; do
  echo "  $f:" | tee -a $LOG
  head -3 "$f" | sed 's/^/    /' | tee -a $LOG
done

# Substitute placeholders
for catalog in /etc/trino/catalog/*.properties; do
  if [ -f "$catalog" ]; then
    echo "  Substituting: $(basename $catalog)" | tee -a $LOG
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

# Log catalog configs AFTER substitution
echo "" | tee -a $LOG
echo "Catalog configs AFTER substitution:" | tee -a $LOG
for f in /etc/trino/catalog/*.properties; do
  echo "  $f:" | tee -a $LOG
  head -3 "$f" | sed 's/^/    /' | tee -a $LOG
done

echo "" | tee -a $LOG
echo "Starting Trino..." | tee -a $LOG
chmod 644 $LOG
exec /usr/lib/trino/bin/run-trino
