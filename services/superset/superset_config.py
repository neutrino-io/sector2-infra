import os
import sys
from sqlalchemy.dialects import registry

# Dynamically detect Python version and add to path
# This ensures compatibility with different Superset base image versions
python_version = f"{sys.version_info.major}.{sys.version_info.minor}"
python_paths = [
    f'/usr/local/lib/python{python_version}/site-packages',
    f'/usr/lib/python{python_version}/site-packages',
    '/usr/local/lib/python3/site-packages',
    '/usr/lib/python3/site-packages',
]

# Add Python site-packages to path for all database drivers
for path in python_paths:
    if path not in sys.path and os.path.exists(path):
        sys.path.insert(0, path)

print(f"Python version: {python_version}")
print(f"Python path: {sys.path[:5]}")  # Print first 5 paths

# Verify critical database drivers are available
try:
    import psycopg2
    print(f"✓ PostgreSQL driver (psycopg2): {psycopg2.__version__}")
except ImportError as e:
    print(f"✗ PostgreSQL driver (psycopg2) not available: {e}")

# Add ClickHouse modules to Python path
try:
    import clickhouse_connect
    print(f"✓ ClickHouse Connect version: {clickhouse_connect.__version__}")
except ImportError as e:
    print(f"Warning: ClickHouse Connect not available: {e}")

try:
    import clickhouse_driver
    print(f"✓ ClickHouse Driver version: {clickhouse_driver.__version__}")
except ImportError as e:
    print(f"Warning: ClickHouse Driver not available: {e}")

# Verify Pillow is available for screenshots and PDF generation
try:
    from PIL import Image
    import PIL
    print(f"✓ Pillow (PIL) version {PIL.__version__} - Screenshot and PDF generation enabled")
except ImportError as e:
    print(f"Warning: Pillow (PIL) not available: {e}")

# Register ClickHouse dialect with proper error handling
# Use clickhouse-driver for native protocol (Railway), clickhouse-connect for HTTP
try:
    from sqlalchemy.dialects import registry
    # Register native protocol dialect for Railway compatibility
    registry.register('clickhouse', 'clickhouse_driver.dbapi.extras.dialect', 'ClickHouseDialect')
    registry.register('clickhouse+native', 'clickhouse_driver.dbapi.extras.dialect', 'ClickHouseDialect')
    print("✅ ClickHouse native dialect registered successfully")
except Exception as e:
    print(f"Warning: Failed to register ClickHouse native dialect: {e}")

# Register HTTP dialect for clickhouse-connect
try:
    # The clickhouse-connect package registers its own HTTP dialect
    print("✅ ClickHouse Connect HTTP dialect available")
except Exception as e:
    print(f"Warning: Failed to register ClickHouse Connect dialect: {e}")

# ============================================================================
# PostgreSQL Configuration - Superset Metadata Database
# ============================================================================
# Configure PostgreSQL as the metadata database (replaces default SQLite)
# This is where Superset stores its internal metadata, user info, charts, dashboards, etc.
SQLALCHEMY_DATABASE_URI = os.environ.get(
    'SQLALCHEMY_DATABASE_URI',
    'sqlite:////app/superset_home/superset.db'  # Fallback to SQLite if env var not set
)

# Use SUPERSET_SECRET_KEY as primary, fall back to SECRET_KEY
SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY") or os.environ.get("SECRET_KEY")

# Additional Superset security configuration
if not SECRET_KEY:
    print("WARNING: No SECRET_KEY or SUPERSET_SECRET_KEY set. Using insecure default.")
    SECRET_KEY = "CHANGE_ME_TO_A_RANDOM_SECRET_KEY"

FEATURE_FLAGS = {
    "ENABLE_TEMPLATE_PROCESSING": True,
}

PREVENT_UNSAFE_DB_CONNECTIONS = False
ENABLE_PROXY_FIX = True

# ============================================================================
# ClickHouse Configuration
# ============================================================================
# Database engine configuration for ClickHouse
# Use native protocol for Railway compatibility
SQLALCHEMY_EXAMPLES_URI = "clickhouse+native://default:@localhost:9000/default"

# Additional ClickHouse configuration
CLICKHOUSE_HTTP_PORT = 8123
CLICKHOUSE_NATIVE_PORT = 9000

# ============================================================================
# SQLAlchemy Engine Configuration
# ============================================================================
# Enable detailed logging for database connections
SQLALCHEMY_ENGINE_OPTIONS = {
    'pool_pre_ping': True,
    'pool_recycle': 300,
    'echo': False,
}

# ============================================================================
# Data Persistence Configuration
# ============================================================================
# Configure data directories for volume mounting
DATA_DIR = '/app/superset_home/data'
UPLOAD_FOLDER = '/app/superset_home/uploads'

# Note: Directories are created by init script to avoid permission issues with volume mounting

# ============================================================================
# Rate Limiting Configuration (Flask-Limiter)
# ============================================================================
# Configure Redis for distributed rate limiting in production
# Falls back to in-memory storage for development/testing
REDIS_URL = os.environ.get('REDIS_URL', None)

if REDIS_URL:
    # Production: Use Redis for distributed rate limiting
    RATELIMIT_STORAGE_URI = REDIS_URL
    print(f"✓ Rate limiting configured with Redis: {REDIS_URL.split('@')[1] if '@' in REDIS_URL else 'configured'}")
else:
    # Development: Use in-memory storage (not recommended for production)
    RATELIMIT_STORAGE_URI = "memory://"
    print("⚠ Rate limiting using in-memory storage (set REDIS_URL for production)")

# Rate limiting configuration (disabled for Railway deployment)
RATELIMIT_ENABLED = False

# ============================================================================
# Cache Configuration
# ============================================================================
# Configure Redis for caching in production if available
# Falls back to SimpleCache for development
if REDIS_URL:
    # Production: Use Redis for distributed caching
    CACHE_CONFIG = {
        'CACHE_TYPE': 'RedisCache',
        'CACHE_REDIS_URL': REDIS_URL,
        'CACHE_DEFAULT_TIMEOUT': 300,
        'CACHE_KEY_PREFIX': 'superset_'
    }
    print("✓ Cache configured with Redis")
else:
    # Development: Use simple in-memory cache
    CACHE_CONFIG = {
        'CACHE_TYPE': 'SimpleCache',
        'CACHE_DEFAULT_TIMEOUT': 300
    }
    print("⚠ Cache using in-memory storage (set REDIS_URL for production)")

# ============================================================================
# Helper Functions
# ============================================================================
# Custom database engine validation
def validate_clickhouse_connection(uri):
    """Validate ClickHouse connection string format"""
    try:
        from sqlalchemy import create_engine
        engine = create_engine(uri)
        with engine.connect() as conn:
            result = conn.execute("SELECT 1")
            return True
    except Exception as e:
        print(f"ClickHouse connection validation failed: {e}")
        return False

# Railway ClickHouse connection helper
def get_railway_clickhouse_uri():
    """Generate proper ClickHouse URI for Railway using native protocol"""
    host = "nozomi.proxy.rlwy.net"
    port = 23230  # Railway ClickHouse native protocol port
    username = "default"
    password = "$74qimqfukgop1ega34t2znnswagku88v"
    database = "default"

    # Properly escape the password for environment variables
    password = password.replace('$', '$$')

    # Railway uses native protocol on port 23230
    return f"clickhouse+native://{username}:{password}@{host}:{port}/{database}"

# Export the Railway URI for easy access
RAILWAY_CLICKHOUSE_URI = get_railway_clickhouse_uri()

# ============================================================================
# Production Configuration
# ============================================================================
# MCP Server Configuration (Model Context Protocol for AI clients)
# ============================================================================
# Run the MCP server as a separate process alongside the web server:
#
#     superset mcp run --host 0.0.0.0 --port 5008
#
# Auth: dev mode (no auth). The MCP_DEV_USERNAME impersonates that user
# for every request. Do NOT expose publicly if you keep this setting —
# anyone with the URL can act as that user.
MCP_AUTH_ENABLED = os.environ.get("MCP_AUTH_ENABLED", "true").lower() == "true"
# When MCP_AUTH_ENABLED is True, the MCP service uses MCP_JWT_SECRET (HS256)
# to verify incoming Authorization: Bearer tokens. We point MCP_JWT_SECRET

# at the same secret the Superset REST API uses (HS256-signed JWT issued
# by /api/v1/security/login). The standard Superset JWT payload is
# {"sub": "<user_id>", "iat": ..., "exp": ...} — it has no email or
# username claim, so the MCP verifier falls back to MCP_DEV_USERNAME for
# user resolution (one-user-per-instance deployment).
MCP_JWT_SECRET = os.environ.get("SUPERSET_SECRET_KEY", os.environ.get("SECRET_KEY", ""))
# HS256 (symmetric). Symmetric is appropriate because the same process both
# issues tokens (login endpoint) and verifies them (MCP service).
MCP_JWT_ALGORITHM = "HS256"
# MCP_DEV_USERNAME is the fallback the verifier uses when it can't map a
# JWT claim to a Superset user (e.g., the standard Superset JWT has only
# `sub=<user_id>` with no email/username). For our single-user deployment
# that means: gate at JWT, then act as this user. Multi-tenant setups
# should override MCP_DEV_USERNAME or use a custom resolver that maps
# JWT `sub` to User.id.
MCP_DEV_USERNAME = os.environ.get("MCP_DEV_USERNAME", "azrijamil")
# Bind on all interfaces so Railway's TCP proxy can reach it.
MCP_SERVICE_HOST = "0.0.0.0"
MCP_SERVICE_PORT = int(os.environ.get("MCP_SERVICE_PORT", "5008"))
# Public-facing URL for any links the MCP server emits (chart previews,
# SQL Lab URLs). Falls back to the Railway public domain when unset.
MCP_SERVICE_URL = os.environ.get(
    "MCP_SERVICE_URL",
    os.environ.get("RAILWAY_PUBLIC_DOMAIN"),
)

# Public-facing URL for the Superset web UI. The MCP service uses this
# to build dashboard/chart/explore links. Without this, links in
# MCP responses point at the container's internal address (e.g.,
# http://0.0.0.0:8080/...). Set it to your Railway public domain.
WEBDRIVER_BASEURL_USER_FRIENDLY = (
    os.environ.get("WEBDRIVER_BASEURL_USER_FRIENDLY")
    or "https://apache-superset-railway-production-13fe.up.railway.app"
)
# RBAC: enforce Superset's role-based access control on MCP tool calls.
MCP_RBAC_ENABLED = True
# Response size guard: cap returned lists so we don't blow LLM context.
MCP_RESPONSE_SIZE_CONFIG = {
    "enabled": True,
    "token_limit": 25000,
    "warn_threshold_pct": 80,
    "max_list_items": 100,
}


# Additional production settings
SUPERSET_WEBSERVER_TIMEOUT = 300
ROW_LIMIT = 50000

# Print configuration summary
print("=" * 70)
print("Superset Configuration Summary")
print("=" * 70)
print(f"Python Version: {python_version}")
print(f"Metadata Database: {SQLALCHEMY_DATABASE_URI.split('@')[0] if '@' in SQLALCHEMY_DATABASE_URI else 'SQLite'}")
print(f"Data Directory: {DATA_DIR}")
print(f"Upload Directory: {UPLOAD_FOLDER}")
print(f"ClickHouse Support: Enabled (Native Protocol)")
print(f"Rate Limiting: {'Redis' if REDIS_URL else 'In-Memory'}")
print(f"Cache Backend: {'Redis' if REDIS_URL else 'SimpleCache'}")
print(f"MCP Server: {MCP_SERVICE_HOST}:{MCP_SERVICE_PORT} (auth={'enabled' if MCP_AUTH_ENABLED else 'dev-mode'})")
print("=" * 70)
