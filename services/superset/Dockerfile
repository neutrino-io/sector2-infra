FROM apache/superset:latest

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libmariadb-dev \
    unixodbc \
    unixodbc-dev \
    libpq-dev \
    gcc \
    g++ \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Detect Python version and store it for later use
RUN PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')") && \
    echo "Detected Python version: $PYTHON_VERSION" && \
    echo "export PYTHON_VERSION=$PYTHON_VERSION" >> /etc/environment

# Install Python dependencies to the virtual environment
# The Superset base image uses a venv at /app/.venv/lib/python3.10/site-packages
# Install both clickhouse-connect (HTTP) and clickhouse-driver (native) for compatibility
RUN /usr/local/bin/pip install --no-cache-dir \
    --target=/app/.venv/lib/python3.10/site-packages \
    clickhouse-connect[sqlalchemy] \
    clickhouse-driver \
    trino

# Install additional database drivers to the venv
RUN /usr/local/bin/pip install --no-cache-dir \
    --target=/app/.venv/lib/python3.10/site-packages \
    psycopg2-binary \
    pymongo \
    pymssql \
    pyodbc \
    mysqlclient

# Install Pillow for screenshot and PDF generation features
# This enables dashboard exports, reports, and thumbnails
RUN /usr/local/bin/pip install --no-cache-dir \
    --target=/app/.venv/lib/python3.10/site-packages \
    pillow

# Install ECharts visualization plugin
# This enables echarts_* chart types (bar, line, area, scatter, etc.)
RUN /usr/local/bin/pip install --no-cache-dir \
    --target=/app/.venv/lib/python3.10/site-packages \
    apache-superset[echarts]

# Install FastMCP (required by superset/mcp_service) and uvicorn (ASGI server)
RUN /usr/local/bin/pip install --no-cache-dir \
    --target=/app/.venv/lib/python3.10/site-packages \
    fastmcp uvicorn

# Verify psycopg2 installation
RUN python3 -c "import psycopg2; print(f'✓ psycopg2 version: {psycopg2.__version__}')"

# Verify Pillow installation
RUN python3 -c "from PIL import Image; import PIL; print(f'✓ Pillow version: {PIL.__version__}')"

# Create persistent data directories
# These will be mounted as volumes in Railway
RUN mkdir -p /app/superset_home/data && \
    mkdir -p /app/superset_home/uploads && \
    mkdir -p /app/superset_home/logs && \
    chown -R superset:superset /app/superset_home

# Create scripts directory for db_upgrade_safe.py
RUN mkdir -p /app/scripts

# Environment variables
ENV ADMIN_USERNAME=$ADMIN_USERNAME
ENV ADMIN_EMAIL=$ADMIN_EMAIL
ENV ADMIN_PASSWORD=$ADMIN_PASSWORD

# Copy configuration files
COPY superset_init.sh ./superset_init.sh
RUN chmod +x ./superset_init.sh

COPY db_upgrade_safe.py /app/scripts/db_upgrade_safe.py
RUN chmod +x /app/scripts/db_upgrade_safe.py

# Auto-load the FAB patches for every Python process (gunicorn workers,
# ad-hoc `python3` invocations, etc.). sitecustomize.py is run by Python's
# site initialization on every startup; placing it in the venv's
# site-packages ensures all of Superset's processes pick it up.
COPY sitecustomize.py /app/.venv/lib/python3.10/site-packages/sitecustomize.py

COPY superset_config.py /app/
COPY clickhouse_railway_engine.py /app/

# Configure Superset paths and application
# ASGI app: serves Flask (Superset UI) + FastMCP (MCP) on port 8088.
COPY asgi_app.py /app/asgi_app.py
ENV SECRET_KEY=$SECRET_KEY
ENV SUPERSET_HOME=/app/superset_home
ENV FLASK_APP=superset.app:create_app()

# Set Python path dynamically based on detected Python version
# This ensures all installed packages are available
RUN PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')") && \
    echo "export PYTHONPATH=/app:/usr/local/lib/python${PYTHON_VERSION}/site-packages:/usr/lib/python${PYTHON_VERSION}/site-packages:\$PYTHONPATH" >> /etc/profile.d/python_path.sh && \
    chmod +x /etc/profile.d/python_path.sh

# Set PYTHONPATH environment variable for runtime
ENV PYTHONPATH=/app:/usr/local/lib/python3/site-packages:/usr/lib/python3/site-packages

# Verify all database drivers are installed before switching user
RUN echo "====== Verifying Database Drivers ======" && \
    python3 -c "import clickhouse_driver; print(f'✓ clickhouse-driver: {clickhouse_driver.__version__}')" && \
    python3 -c "import trino; from trino.dbapi import connect; print('✓ trino: imported successfully')" && \
    python3 -c "import pymongo; print(f'✓ pymongo: {pymongo.__version__}')" && \
    python3 -c "import clickhouse_connect; print('✓ clickhouse-connect: imported successfully')" && \
    python3 -c "from PIL import Image; import PIL; print(f'✓ Pillow: {PIL.__version__}')" && \
    python3 -c "import superset; print('✓ Superset: imported successfully')" && \
    echo "====== All drivers verified successfully ======"

# Note: Staying as root to allow init script to create volume directories
# Init script will switch to superset user after directory setup
# USER superset

# Expose port (Railway will map this automatically)
# Expose ports (Railway maps the web server on 8088 and the MCP server
# on 5008).
EXPOSE 8088 5008

ENTRYPOINT ["./superset_init.sh"]
