FROM trinodb/trino:435

USER root

# Ensure catalog directory exists
RUN mkdir -p /etc/trino/catalog && \
    chown -R trino:trino /etc/trino

USER trino

# Copy catalog template configs (placeholders get substituted at runtime)
COPY --chown=trino:trino config/ /etc/trino/catalog/

# Copy startup script (bash + curl + sed already in base image)
COPY --chown=trino:trino trino_init.sh /etc/trino/trino_init.sh

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1

# Override the base image ENTRYPOINT so our init script runs first
ENTRYPOINT ["/bin/bash", "/etc/trino/trino_init.sh"]
