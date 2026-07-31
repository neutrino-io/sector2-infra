FROM trinodb/trino:435

USER root
RUN mkdir -p /etc/trino/catalog && chown -R trino:trino /etc/trino

USER trino

# Catalog configs (placeholders substituted at runtime by run-trino.sh)
COPY --chown=trino:trino services/trino/config/ /etc/trino/catalog/

# Init script: ENTRYPOINT always runs regardless of Railway monorepo startCommand issues
# This is the ONLY reliable way to do env var substitution at runtime on Railway
COPY --chown=trino:trino services/trino/run-trino.sh /usr/local/bin/run-trino.sh
ENTRYPOINT ["/usr/local/bin/run-trino.sh"]

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1
