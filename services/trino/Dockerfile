FROM trinodb/trino:435

USER root

# Install gettext-base for envsubst + curl for healthcheck
RUN apt-get update && apt-get install -y curl gettext-base && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure catalog directory exists
RUN mkdir -p /etc/trino/catalog && \
    chown -R trino:trino /etc/trino

USER trino

# Copy catalog template configs (placeholders get substituted at runtime)
COPY --chown=trino:trino config/ /etc/trino/catalog/

# Copy startup script that substitutes env vars then launches Trino
COPY --chown=trino:trino trino_init.sh /etc/trino/trino_init.sh

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1
