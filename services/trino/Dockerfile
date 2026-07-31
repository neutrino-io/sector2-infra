FROM trinodb/trino:435

USER root

# Install gettext-base for envsubst (in case we need it for runtime substitution)
RUN apt-get update && apt-get install -y gettext-base bash && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure catalog directory exists and is writable by trino user
RUN mkdir -p /etc/trino/catalog && \
    chown -R trino:trino /etc/trino

# trino_init.sh script that substitutes env vars and runs the launcher
COPY --chown=trino:trino trino_init.sh /etc/trino/trino_init.sh
RUN chmod +x /etc/trino/trino_init.sh

USER trino

# Copy catalog template configs (with __R2_*__ placeholders)
COPY --chown=trino:trino config/ /etc/trino/catalog/

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1

# Use Trino's launcher as the entrypoint, with our init script as the CMD
# When Railway sets startCommand, it overrides CMD. The init script will
# run as CMD via the launcher (which calls it as a sub-process via /bin/sh)
# Actually that won't work since launcher doesn't exec the CMD as a script.
# 
# Better: use the launcher directly with the config-dir flag pointing
# to a substituted directory. We don't have a pre-substituted dir though.
# 
# Final approach: use bash -c in startCommand to do substitution + exec
# Set CMD to a no-op so Railway's startCommand is the only entry
CMD ["echo", "Use startCommand to run trino_init.sh"]
