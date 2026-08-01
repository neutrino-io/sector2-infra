FROM trinodb/trino:483

USER root

# Create necessary directories for catalog templates and rendered configs.
# We do NOT install gettext/envsubst because the base image is RHEL 10
# (no apt-get/dnf). Our entrypoint does the ${VAR} substitution in pure bash.
RUN mkdir -p /etc/trino/catalog /etc/trino/template && chown -R trino:trino /etc/trino

USER trino

# Non-secret R2 endpoints only. Secrets (R2_CATALOG_TOKEN, R2_ACCESS_KEY,
# R2_SECRET_KEY) are set ONLY via Railway Variables and never committed.
ENV R2_ICEBERG_REST_URI="https://catalog.cloudflarestorage.com/203a605533f37eb35da80dcf03a7bed6/gyhc40sdz8-ivj8v3841x-bronze-storage"
ENV R2_ICEBERG_WAREHOUSE="203a605533f37eb35da80dcf03a7bed6_gyhc40sdz8-ivj8v3841x-bronze-storage"
ENV R2_S3_ENDPOINT="https://203a605533f37eb35da80dcf03a7bed6.r2.cloudflarestorage.com"

# Catalog templates use ${VAR} - rendered by entrypoint at container start.
# Templates copied to /etc/trino/template/. The entrypoint renders them to /etc/trino/catalog/.
COPY --chown=trino:trino template/ /etc/trino/template/

# Entrypoint: bash-based envsubst then launch Trino.
COPY --chown=trino:trino trino-entrypoint.sh /usr/local/bin/trino-entrypoint.sh
RUN chmod +x /usr/local/bin/trino-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/trino-entrypoint.sh"]
