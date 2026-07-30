FROM trinodb/trino:435

USER root

# Health check dependency
RUN apt-get update && apt-get install -y curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure catalog directory exists with correct ownership
RUN mkdir -p /etc/trino/catalog && \
    chown -R trino:trino /etc/trino

USER trino

# Copy catalog configs (iceberg, clickhouse, mart)
COPY --chown=trino:trino config/ /etc/trino/catalog/

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1

# Default Trino entrypoint (from base image) — launches coordinator + worker in one process
# For production: split into coordinator + worker services (same image, different configs)