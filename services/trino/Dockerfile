FROM trinodb/trino:435

USER root

# Ensure catalog directory exists
RUN mkdir -p /etc/trino/catalog && \
    chown -R trino:trino /etc/trino

# Init script that renders configs from env vars then execs Trino
COPY --chown=trino:trino trino_init.sh /opt/trino_init.sh
RUN chmod +x /opt/trino_init.sh

USER trino

# Copy catalog template configs (with __R2_*__ placeholders)
COPY --chown=trino:trino config/ /etc/trino/catalog/

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1

# Use the init script as the entrypoint (no override of base image's launcher)
# When Railway sets startCommand, it becomes CMD which gets appended to ENTRYPOINT
# We want: [entrypoint: /opt/trino_init.sh] [cmd: optional args]
# Trino's launcher reads this as: /usr/lib/trino/bin/launcher run /opt/trino_init.sh
# The launcher will try to use /opt/trino_init.sh as a config dir path
# which fails silently.
# 
# Better: use exec form in entrypoint so it gets ALL future args
# This means we MUST NOT set CMD/startCommand; just let the entrypoint run alone
ENTRYPOINT ["/bin/bash", "/opt/trino_init.sh"]
