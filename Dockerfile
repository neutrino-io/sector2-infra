FROM trinodb/trino:435

USER root
RUN mkdir -p /etc/trino/catalog && chown -R trino:trino /etc/trino

USER trino

# Catalog configs
COPY --chown=trino:trino services/trino/config/ /etc/trino/catalog/

# Write a startup log to prove CMD runs
RUN echo "Dockerfile built at $(date)" > /dockerfile-built.log

# Test: use CMD to write a log file
CMD ["bash", "-c", "echo 'CMD_executed_at_$(date)' >> /tmp/cmd-ran.log && cat /etc/trino/catalog/*.properties | head -3 >> /tmp/cmd-ran.log && exec /usr/lib/trino/bin/run-trino"]
