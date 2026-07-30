FROM trinodb/trino:435

USER root

# Install envsubst (alpine variant of gettext) and curl for healthcheck
RUN apt-get update && apt-get install -y curl gettext-base && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure catalog directory exists
RUN mkdir -p /etc/trino/catalog && \
    chown -R trino:trino /etc/trino

USER trino

# Copy catalog template configs (will have env vars substituted at runtime)
COPY --chown=trino:trino config/ /etc/trino/catalog/

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1

# Use default Trino entrypoint (launcher reads configs from /etc/trino/catalog)
# Entrypoint already runs run-trino which substitutes env vars in configs at startup
