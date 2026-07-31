FROM trinodb/trino:483

# Cache bust 2026-07-31_21:25

USER root
RUN mkdir -p /etc/trino/catalog && chown -R trino:trino /etc/trino

USER trino

# Non-sensitive defaults for R2 config (committed to git, safe to expose).
# Railway Variables override these at container runtime.
# Trino's airlift Config class expands ${ENV_VAR} in properties.
ENV R2_ICEBERG_REST_URI="https://catalog.cloudflarestorage.com/203a605533f37eb35da80dcf03a7bed6/gyhc40sdz8-ivj8v3841x-bronze-storage"
ENV R2_ICEBERG_WAREHOUSE="203a605533f37eb35da80dcf03a7bed6_gyhc40sdz8-ivj8v3841x-bronze-storage"
ENV R2_S3_ENDPOINT="https://203a605533f37eb35da80dcf03a7bed6.r2.cloudflarestorage.com"
ENV R2_ACCESS_KEY="a032b0220462cfce8fe7dc681135883d"
# R2_CATALOG_TOKEN and R2_SECRET_KEY are sensitive — set ONLY in Railway Variables

# Catalog configs with ${ENV_VAR} placeholders
COPY --chown=trino:trino services/trino/config/ /etc/trino/catalog/

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1
