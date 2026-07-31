# Trino 483 base image (R2 Data Catalog Bearer auth fixes from 482+)
FROM trinodb/trino:483

USER root
RUN mkdir -p /etc/trino/catalog && chown -R trino:trino /etc/trino

USER trino

# Non-secret R2 endpoints only (URLs are public knowledge).
# R2_CATALOG_TOKEN, R2_ACCESS_KEY, R2_SECRET_KEY must be set ONLY via Railway Variables.
ENV R2_ICEBERG_REST_URI="https://catalog.cloudflarestorage.com/203a605533f37eb35da80dcf03a7bed6/gyhc40sdz8-ivj8v3841x-bronze-storage"
ENV R2_ICEBERG_WAREHOUSE="203a605533f37eb35da80dcf03a7bed6_gyhc40sdz8-ivj8v3841x-bronze-storage"
ENV R2_S3_ENDPOINT="https://203a605533f37eb35da80dcf03a7bed6.r2.cloudflarestorage.com"

# Catalog configs (relative to /services/trino since this is services/trino/Dockerfile)
COPY --chown=trino:trino services/trino/config/ /etc/trino/catalog/

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1
