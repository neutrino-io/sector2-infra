FROM trinodb/trino:435

USER root

# Install gettext-base for envsubst (if needed)
RUN apt-get update && apt-get install -y gettext-base && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure catalog directory exists
RUN mkdir -p /etc/trino/catalog && \
    chown -R trino:trino /etc/trino

# trino_init.sh script (runs as part of ENTRYPOINT)
COPY --chown=trino:trino trino_init.sh /etc/trino/trino_init.sh
RUN chmod +x /etc/trino/trino_init.sh

USER trino

# Copy catalog configs (placeholders get substituted at runtime by trino_init.sh)
COPY --chown=trino:trino config/ /etc/trino/catalog/

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1

# Override ENTRYPOINT to run our init script
# When Railway sets a startCommand, it becomes the CMD that gets appended to ENTRYPOINT
# So: ENTRYPOINT=/etc/trino/trino_init.sh CMD=<trino-args>
# We want: init script runs, then execs Trino launcher
ENTRYPOINT ["/etc/trino/trino_init.sh"]
