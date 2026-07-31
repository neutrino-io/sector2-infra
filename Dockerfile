FROM trinodb/trino:435

USER root
RUN mkdir -p /etc/trino/catalog && chown -R trino:trino /etc/trino

USER trino

# Catalog configs
COPY --chown=trino:trino services/trino/config/ /etc/trino/catalog/

# Minimal ENTRYPOINT that writes to a file + stdout, then runs Trino
COPY --chown=trino:trino services/trino/run-trino.sh /usr/local/bin/run-trino.sh
RUN chmod +x /usr/local/bin/run-trino.sh

# Use shell form to ensure it runs
ENTRYPOINT ["/bin/bash", "-c", "echo 'ENTRYPOINT_ran_at_$(date)' > /tmp/entry.log && cat /usr/local/bin/run-trino.sh | head -3 >> /tmp/entry.log && echo 'About to exec trino' >> /tmp/entry.log && exec /usr/lib/trino/bin/launcher run --etc-dir /tmp/trino-etc"]

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1
