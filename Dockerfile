FROM trinodb/trino:435

USER root

# Write a single test file
RUN echo "BUILD_OK" > /tmp/build-ok.txt

USER trino

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -f http://localhost:8080/v1/info || exit 1
