---
name: railway-asgi-healthcheck-gotcha
description: Railway's deploy-time health probe interacts badly with custom ASGI ProxyRouter code, causing "Session terminated, killing shell..." after ~6 minutes
triggers:
  - "Session terminated, killing shell"
  - "Railway container killed 6 minutes"
  - "ASGI ProxyRouter Railway deployment failed"
  - "Railway healthcheckPath Custom ASGI app"
  - "railway deployment Crashed healthy app"
---

# Railway ASGI Healthcheck Gotcha

## The Insight
Railway's deploy-time HTTP health probe does NOT just verify the service is up — it interacts with the bash session manager that wraps your container's PID 1. When Railway probes a custom ASGI app via `healthcheckPath`, the session manager treats the response stream as "abnormal" and triggers a session cleanup after ~5-7 minutes, killing the container with `Session terminated, killing shell...`. The fix is to **disable Railway's deploy-time health probe entirely** (`healthcheckPath=""`, `healthcheckTimeout=null`) while keeping any in-app `/health` endpoint you want for external monitors.

## Why This Matters
This gotcha masquerades as a code bug. You see your app start successfully ("Uvicorn running on http://0.0.0.0:8088"), all logs look healthy, no exceptions — and yet the container is killed and the deployment marked `Crashed`. Worst part: **the failure is identical whether your code is correct or broken**. We verified this by deploying the original known-working `apache-superset-railway` repo side-by-side and watching it fail with the exact same pattern (`Session terminated, killing shell...` at the ~6 minute mark).

## Recognition Pattern
Apply this skill when ALL of these match:
- Deploying an ASGI app (FastAPI/Starlette/custom ProxyRouter) on Railway
- Container starts successfully, prints "Uvicorn running..." or equivalent
- ~5-7 minutes after startup, logs show `Session terminated, killing shell...` followed by `Stopping Container`
- No exceptions, no OOM, no port binding errors
- Deployment marked `FAILED` or `Crashed`
- The bash session manager (PID 1 wrapper) is sending SIGTERM after a period of "idle" even though the app is actively listening

**Smoking gun**: search for `Session terminated, killing shell` in your deployment logs.

## The Approach
**Decision tree for Railway ASGI deployments:**

1. **First**: Before deploying to Railway, check if you NEED Railway's deploy-time health probe. If your service is a long-running web server with its own `/health` route, the answer is usually **no** — Railway will only probe during deployment validation, not at runtime.

2. **Configure via API mutation** (the `railway.toml` block is NOT applied to auto-created services):
   ```graphql
   mutation {
     serviceInstanceUpdate(
       environmentId: "..."
       serviceId: "..."
       input: {
         healthcheckPath: ""
         healthcheckTimeout: null
       }
     )
   }
   ```
   Setting to empty string + null disables the deploy-time probe. (`null` alone for `healthcheckPath` is rejected by the schema.)

3. **Always set PORT env var**: Railway's edge defaults to forwarding to port `8080`. If your app binds elsewhere (e.g. `8088` for Superset uvicorn), set `PORT=8088` as a Railway variable so the edge knows where to route. Without this you'll get `502 Application failed to respond` even though the app is healthy.

4. **Verify with the in-app endpoint**: After deploy, your service's own `/health` route should still respond with 200 — that's for external monitors. Railway just won't probe it.

5. **Proving it's not your code**: When stuck on a "container killed mysteriously" problem, deploy the **known-working reference repo** as a separate Railway service with identical config. If both fail identically, the bug is platform-level, not code-level. This saves hours of chasing phantom code bugs.

## Example
The fix in `services/superset/railway.toml` and Railway service config:

```toml
[deploy]
startCommand = "./superset_init.sh"
# healthcheckPath intentionally NOT set
# healthcheckTimeout intentionally NOT set
```

```bash
# Set via Railway CLI or API:
PORT=8088
```

Diagnostic commands:
```bash
# Check current health check config:
/tmp/railway api <<EOF
query {
  serviceInstance(environmentId: "...", serviceId: "...") {
    healthcheckPath
    healthcheckTimeout
  }
}
EOF

# Compare against a known-working service (trino) in the same project:
# Working services have healthcheckPath: null
# Failing services have healthcheckPath: "/health" + custom ProxyRouter
```

## Related Gotcha
The same session killer triggers when Railway probes a **non-trivial ASGI response** that holds the connection open or streams data. Simple endpoints that return `{type: "http.response.start", status: 200, headers: [...]} ; {type: "http.response.body", body: b"OK"}` in `ProxyRouter.__call__` are what trigger it. If you must have Railway's health check, serve it from a separate HTTP endpoint that's NOT wrapped in your custom ProxyRouter.