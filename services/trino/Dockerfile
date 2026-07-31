FROM trinodb/trino:435

USER root

RUN mkdir -p /etc/trino/catalog && chown -R trino:trino /etc/trino

USER trino

COPY --chown=trino:trino config/ /etc/trino/catalog/

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1

# Use the base image's default ENTRYPOINT (no override)
