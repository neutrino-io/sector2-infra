FROM trinodb/trino:435

USER root

RUN mkdir -p /etc/trino/catalog && chown -R trino:trino /etc/trino

USER trino

# Catalog configs (placeholders substituted at runtime by run-trino.sh)
COPY --chown=trino:trino services/trino/config/ /etc/trino/catalog/

# Script to substitute env vars and launch Trino
COPY --chown=trino:trino services/trino/run-trino.sh /etc/trino/run-trino.sh

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1
