FROM trinodb/trino:435

USER root

# Ensure catalog directory exists
RUN mkdir -p /etc/trino/catalog && \
    chown -R trino:trino /etc/trino

USER trino

# Copy catalog configs
COPY --chown=trino:trino config/ /etc/trino/catalog/

# Build marker
COPY --chown=trino:trino config/iceberg.properties /opt/build-marker.txt

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1
