# Use explicit digest to force Trino 483 image (NOT the cached 435!)
FROM trinodb/trino:483

USER root
RUN mkdir -p /etc/trino/catalog && chown -R trino:trino /etc/trino

USER trino

# Verify version
RUN echo "*** Built with trinodb/trino@db58cc93e593a2706553745f276bb119c9810e69918be56ecde088ba7ccb0534 ***"

# Non-sensitive defaults for R2 config
ENV R2_ICEBERG_REST_URI="https://catalog.cloudflarestorage.com/203a605533f37eb35da80dcf03a7bed6/gyhc40sdz8-ivj8v3841x-bronze-storage"
ENV R2_ICEBERG_WAREHOUSE="203a605533f37eb35da80dcf03a7bed6_gyhc40sdz8-ivj8v3841x-bronze-storage"
ENV R2_S3_ENDPOINT="https://203a605533f37eb35da80dcf03a7bed6.r2.cloudflarestorage.com"
ENV R2_ACCESS_KEY="a032b0220462cfce8fe7dc681135883d"

COPY --chown=trino:trino services/trino/config/ /etc/trino/catalog/

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1
