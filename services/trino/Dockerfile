FROM trinodb/trino:435

USER root

# Ensure catalog directory exists and is writable by trino user
RUN mkdir -p /etc/trino/catalog && \
    chown -R trino:trino /etc/trino

# Init script that renders configs from env vars then execs Trino
COPY --chown=trino:trino trino_init.sh /etc/trino/trino_init.sh
RUN chmod +x /etc/trino/trino_init.sh

USER trino

# Copy catalog template configs
COPY --chown=trino:trino config/ /etc/trino/catalog/

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1

# Override entrypoint to run trino_init.sh first
ENTRYPOINT ["/bin/bash", "/etc/trino/trino_init.sh"]
