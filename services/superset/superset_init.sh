#!/bin/bash
set -e

echo "======================================================================"
echo "Superset Initialization Starting"
echo "======================================================================"

# Create data directories if they don't exist (needed for volume mounting)
# Running as root to handle volume permissions
echo "Ensuring data directories exist with correct permissions..."
mkdir -p /app/superset_home/data
mkdir -p /app/superset_home/uploads
mkdir -p /app/superset_home/logs
chown -R superset:superset /app/superset_home
echo "✓ Data directories ready with superset user ownership"

# Wait for the application to fully initialize
echo "Waiting for application initialization..."
sleep 5

# Test database connectivity with retry/backoff.
#
# On Railway, Postgis can take a few seconds to accept TCP connections
# after Superset starts. A single-shot connect() check fails with
# `Connection refused` even when the URI is correct. Retry up to 5 times
# with 2s sleep; succeed on the first successful connect.
echo "Testing PostgreSQL database connectivity..."
python3 -c "
import os
import sys
import time
from sqlalchemy import create_engine, text

db_uri = os.environ.get('SQLALCHEMY_DATABASE_URI', 'sqlite:////app/superset_home/superset.db')
print(f'Database URI: {db_uri.split(\"@\")[0] if \"@\" in db_uri else \"SQLite\"}')

max_attempts = 5
delay_seconds = 2
for attempt in range(1, max_attempts + 1):
    try:
        engine = create_engine(db_uri)
        with engine.connect() as conn:
            conn.execute(text('SELECT 1'))
        print(f'✓ Database connection successful (attempt {attempt})')
        sys.exit(0)
    except Exception as e:
        print(f'✗ Database connection failed (attempt {attempt}/{max_attempts}): {e}')
        if attempt < max_attempts:
            time.sleep(delay_seconds)
        else:
            sys.exit(1)
" || {
    echo "ERROR: Database connection failed after retries. Please check your SQLALCHEMY_DATABASE_URI"
    exit 1
}

# Import ClickHouse modules (both HTTP and Native drivers)
echo "======================================================================"
echo "Testing ClickHouse Driver Support"
echo "======================================================================"
python3 -c "
import sys
print('Python path:', sys.path)
try:
    import clickhouse_connect
    print('✓ ClickHouse Connect (HTTP) imported successfully')
    print('  Version:', clickhouse_connect.__version__)
    print('  Features: High-performance HTTP driver with SQLAlchemy support')
except ImportError as e:
    print('✗ ClickHouse Connect import failed:', e)

try:
    import clickhouse_driver
    print('✓ ClickHouse Driver (Native) imported successfully')
    print('  Version:', clickhouse_driver.__version__)
    print('  Features: Native protocol support for Railway compatibility')
except ImportError as e:
    print('✗ ClickHouse Driver import failed:', e)

try:
    from sqlalchemy import create_engine
    print('✓ SQLAlchemy imported successfully')
except ImportError as e:
    print('✗ SQLAlchemy import failed:', e)

try:
    from sqlalchemy.dialects import registry
    registry.register('clickhouse', 'clickhouse_driver.dbapi.extras.dialect', 'ClickHouseDialect')
    registry.register('clickhouse+native', 'clickhouse_driver.dbapi.extras.dialect', 'ClickHouseDialect')
    print('✓ ClickHouse native dialects registered successfully')
except Exception as e:
    print('✗ Dialect registration failed:', e)

try:
    from PIL import Image
    import PIL
    print(f'✓ Pillow (PIL) version {PIL.__version__} - Screenshot and PDF generation enabled')
except ImportError as e:
    print('✗ Pillow (PIL) not available:', e)
"

echo "======================================================================"
echo "Superset Database Initialization"
echo "======================================================================"

# Start the MCP server in the background BEFORE the slow init steps.
# It binds 0.0.0.0:5008, impersonates MCP_DEV_USERNAME for auth, and
# detaches via setsid so it survives the rest of the init script.
if [ -z "${SKIP_MCP:-}" ]; then
    mkdir -p /app/superset_home/logs
    setsid nohup /app/.venv/bin/superset mcp run \
        --host 0.0.0.0 --port "${MCP_SERVICE_PORT:-5008}" \
        >> /app/superset_home/logs/mcp.log 2>&1 < /dev/null &
    MCP_PID=$!
    echo "✓ MCP server starting (pid: $MCP_PID) — logs at /app/superset_home/logs/mcp.log"
    sleep 3
fi

# Run all Superset commands as superset user (we created dirs as root above)
echo "Switching to superset user for database operations..."
# Upgrade the database schema.
#
# We do NOT use `superset db upgrade` here because of a Superset 1.4.x bug:
# the Flask CLI's with_appcontext decorator does NOT push an app context
# around `create_app()`, but Superset's init_app() calls
# `appbuilder.init_app(app, db.session)` inside create_app(). Flask-AppBuilder's
# SecurityManager.__init__ then runs `db.session.get_bind(mapper=None, ...)`
# against a greenlet-keyed scoped_session whose registry has not been
# populated — yielding `sqlalchemy.exc.NoInspectionAvailable: ... <class
# 'NoneType'>`. Reproduces on every fresh deploy and on Railway volume
# swaps.
#
# db_upgrade_safe.py constructs the app, pushes an explicit app context,
# and runs Alembic migrations directly via Flask-Migrate.
echo "Upgrading Superset metadata database..."
chmod +x /app/scripts/db_upgrade_safe.py 2>/dev/null || true
su -s /bin/bash superset -c "python3 /app/scripts/db_upgrade_safe.py" || {
    echo "ERROR: Database upgrade failed (db_upgrade_safe.py)"
    exit 1
}

# Create admin user.
#
# Same context-pushing workaround: `superset fab create-admin` calls into
# the same broken SecurityManager path. Run it through db_upgrade_safe.py
# which constructs the app + app context first.
echo "Creating admin user..."
su -s /bin/bash superset -c "python3 /app/scripts/db_upgrade_safe.py --admin-only" || {
    echo "Note: Admin user may already exist (this is normal on restart)"
}

# Initialize roles and permissions.
#
# Same context-pushing workaround: `superset init` calls into
# SecurityManager.create_db() which hits the same `get_bind -> None` failure
# path. Run it through db_upgrade_safe.py's init-only mode.
echo "Initializing roles and permissions..."
# Non-fatal: on cold-start (empty metadata DB) the upstream Superset 1.4.x
# `appbuilder.init_app` bug can still fire here. The roles will be seeded
# on the next deploy once Alembic migrations have populated the schema.
su -s /bin/bash superset -c "python3 /app/scripts/db_upgrade_safe.py --init-only" || {
    echo "Note: superset init failed; will retry on next deploy"
}

# Load example data is DISABLED for production
# Uncomment the following lines if you want to load example datasets for testing
# echo "Loading example data..."
# superset load-examples || {
#     echo "Note: Example data loading failed or already loaded (this is normal)"
# }
echo "Skipping example data loading (disabled for production)"

echo "======================================================================"
echo "Superset Initialization Complete"
echo "======================================================================"
echo "Configuration:"
echo "  - Admin Username: $ADMIN_USERNAME"
echo "  - Admin Email: $ADMIN_EMAIL"
echo "  - Database: PostgreSQL"
echo "  - ClickHouse Support: Enabled"
echo "  - Pillow (PIL): Enabled for screenshots and PDFs"
echo "  - Data Directory: /app/superset_home"
echo "  - Example Data: Disabled (production mode)"
echo "======================================================================"
echo "Starting Superset + MCP ASGI server (uvicorn on :8088)..."
echo "======================================================================"
echo "FLASK_APP is set to: $FLASK_APP"
echo "ASGI app: /app/asgi_app.py"
echo "======================================================================"

# The MCP server is now served by the same ASGI app at /mcp (no need for
# a separate process on :5008). The old detached "superset mcp run" is
# intentionally NOT started here.
#
# uvicorn replaces gunicorn. The /usr/bin/run-server.sh we previously
# exec'd (which was gunicorn + the standalone :5008 MCP) is now obsolete
# for this deployment. We run uvicorn directly so both the Flask app and
# the FastMCP server share the same event loop.
mkdir -p /app/superset_home/logs
# Set PYTHONUNBUFFERED so MCP JSON-RPC output is flushed promptly.
export PYTHONUNBUFFERED=1
exec su -s /bin/bash superset -c "cd /app && python3 -m uvicorn asgi_app:app \
    --host 0.0.0.0 \
    --port 8088 \
    --workers 1 \
    --log-level info"
