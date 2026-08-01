"""
Combined ASGI app for Railway deployment.

Serves both:
- Apache Superset (Flask WSGI) at all paths except /mcp
- The official Apache Superset MCP service (FastMCP ASGI) at /mcp

This replaces the previous two-process architecture (gunicorn + standalone
superset mcp run). With Railway exposing only one public port (8088),
we collapsed both onto a single uvicorn worker.

Entrypoint in production:
    python3 -m uvicorn asgi_app:app --host 0.0.0.0 --port 8088

Flask app context for MCP tools:
The Superset MCP server uses Flask's `current_app` to look up
appbuilder, security_manager, db.session, etc. When MCP tool calls
arrive via ASGI, there is no implicit request context. We wrap the
MCP ASGI app with an app context push so `current_app` resolves to
our singleton Flask app.

Auth: the default `mcp` instance is built without an auth provider —
fine for the localhost-only :5008 deployment, unsafe for public
exposure. We use the same `_create_auth_provider` factory the
standalone `superset mcp run` server uses internally to build an auth
provider from the Flask app config, then assign it onto the existing
`mcp` instance before mounting it as ASGI. This keeps all the
`@mcp.tool` decorators registered to the default `mcp` working
unchanged.

Notes:
- FastMCP http_app(path="/mcp", stateless_http=True) means each tool
  call is independent (no session cookie required between calls).
- WSGIMiddleware embeds the Flask WSGI app inside the ASGI hierarchy.
- The custom ProxyRouter tries /mcp first (FastMCP), then falls back
  to Flask WSGI. Mount order alone doesn't allow fallback in Starlette.
- ENABLE_PROXY_FIX and PREFERRED_URL_SCHEME in superset_config.py ensure
  Superset links generated via the MCP are emitted as https://.
"""
import os

# Mirror what superset_init.sh sets up so the WSGI and ASGI halves share state.
os.environ.setdefault("FLASK_APP", "superset.app:create_app()")
os.environ.setdefault("SUPERSET_CONFIG_PATH", "/app/superset_config.py")
os.environ.setdefault("PYTHONPATH",
    "/app:/usr/local/lib/python3/site-packages:/usr/lib/python3/site-packages")
# Public deployment: require JWT auth on the MCP unless the operator
# explicitly opts out via env MCP_AUTH_ENABLED=false.
os.environ.setdefault("MCP_AUTH_ENABLED", "true")

from starlette.applications import Starlette
from starlette.routing import Mount
from starlette.middleware.wsgi import WSGIMiddleware

# Build the Flask app FIRST so the MCP auth factory can read
# MCP_AUTH_ENABLED, MCP_JWT_SECRET, MCP_JWT_ALGORITHM from its config.
from superset.app import create_app as create_superset_app
flask_app = create_superset_app()

# Use the existing default FastMCP instance — it already has all the
# @mcp.tool() decorators registered. We just need to attach an auth
# provider so it's safe to expose publicly.
from superset.mcp_service.app import mcp as fastmcp
from superset.mcp_service.server import _create_auth_provider

auth_provider = _create_auth_provider(flask_app)
if auth_provider is not None:
    fastmcp.auth = auth_provider

mcp_asgi = fastmcp.http_app(
    path="/mcp",
    transport="streamable-http",
    stateless_http=True,
)


class ContextPushingASGI:
    """Wrap a downstream ASGI app so every request runs inside the
    Flask app's `app_context()`. Required because Superset MCP tools call
    `flask.current_app` / `flask.g` / `appbuilder` — these resolve to
    `None` (or raise) when there's no surrounding app context.
    """

    def __init__(self, app, flask_app):
        self.app = app
        self.flask_app = flask_app

    async def __call__(self, scope, receive, send):
        with self.flask_app.app_context():
            await self.app(scope, receive, send)


mcp_with_ctx = ContextPushingASGI(mcp_asgi, flask_app)


class ProxyRouter:
    """ASGI app: route /mcp -> MCP, /health -> 200 OK, else -> Flask WSGI."""

    def __init__(self, mcp_app, flask_wsgi_app):
        self.mcp_app = mcp_app
        self.flask_app = flask_wsgi_app

    async def __call__(self, scope, receive, send):
        path = scope.get("path", "") or ""
        # Health check for Railway (and any other deployment orchestrator)
        if path == "/health" or path == "/healthz":
            await send({"type": "http.response.start", "status": 200, "headers": [(b"content-type", b"text/plain")]})
            await send({"type": "http.response.body", "body": b"OK"})
            return
        if path == "/mcp" or path.startswith("/mcp/"):
            await self.mcp_app(scope, receive, send)
        else:
            await self.flask_app(scope, receive, send)


app = Starlette(
    routes=[Mount("/", app=ProxyRouter(mcp_with_ctx, WSGIMiddleware(flask_app)))],
    lifespan=mcp_asgi.lifespan,
)