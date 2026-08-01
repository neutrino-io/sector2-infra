---
name: trino-railway-deployment
description: Three deployment gotchas for running Trino on Railway - env-var substitution, RHEL 10 base image, and X-Forwarded-For proxy header handling
triggers:
  - Trino 483 on Railway
  - Bearer token format is invalid
  - "${R2_CATALOG_TOKEN}" literal in bootstrap log
  - apt-get not found in Dockerfile
  - HTTP ERROR 406 Server configuration does not allow processing of the X-Forwarded-For header
  - Cannot obtain metadata TrinoException
---

# Trino on Railway Deployment

## The Insight

Trino's official deployment assumptions and Railway's runtime environment collide on three specific points. The mental model:

**Trino assumes:** Debian/Ubuntu base image with `apt-get` and standard util-linux. Env vars are JVM `-D` system properties, NOT substituted into catalog `.properties` files. The HTTP server trusts only direct connections with no `X-Forwarded-*` headers.

**Railway provides:** A hardened runtime with the upstream image unchanged (trinodb/trino:483 is RHEL 10, not Debian). Env vars are injected as `KEY=value` pairs in the container. The edge proxy (`railway-hikari`) injects `X-Forwarded-For` on every request.

When these collide, Trino silently breaks: tokens fail, builds fail with cryptic errors, queries return 406. The fix is to make Trino's container compatible with Railway's reality.

## Why This Matters

Symptoms that look like credential issues are actually deployment assumptions:

- `"Bearer token format is invalid"` from R2 with a working token → Trino sent `${R2_CATALOG_TOKEN}` LITERAL because Trino does NOT do `${ENV}` substitution in catalog `.properties` files. The bootstrap log reveals this: `s3.aws-access-key ---- ${R2_ACCESS_KEY}` (the runtime value column shows the template, not the resolved value).
- `apt-get: command not found` in Dockerfile build → trinodb/trino:483 base image is RHEL 10 (`/etc/os-release` shows `ID="rhel"`), not Debian. Installing `gettext-base` for `envsubst` fails.
- `HTTP ERROR 406 Server configuration does not allow processing of the X-Forwarded-For header` → Railway's edge proxy sends this header on every request; Trino 483 defaults to rejecting it as a security measure.

## Recognition Pattern

When deploying Trino on Railway, check bootstrap log immediately:

```bash
grep "io.trino.bootstrap.catalog.iceberg" /path/to/server.log
```

Look for these lines:
- `iceberg.rest-catalog.oauth2.token                                [REDACTED]        [REDACTED]` paired with `s3.aws-access-key ---- ${R2_ACCESS_KEY}` → substitution not happening (template is in runtime column).
- `iceberg.rest-catalog.security                                    NONE              OAUTH2` → security was correctly set.
- Token works for `SHOW SCHEMAS` (Data Catalog API call) but fails for `SELECT` (S3 data file read) → S3 keys wrong, catalog token fine.

When Dockerfile build fails:
```
/bin/sh: line 1: apt-get: command not found
```
→ RHEL 10 base image, use pure-bash or RHEL-native installers.

When every external request returns 406:
```
HTTP ERROR 406 Server configuration does not allow processing of the X-Forwarded-For header
```
→ Railway proxy headers being rejected.

## The Approach

**Principle: Trino's official image is not Railway-ready out of the box. Add a thin compatibility layer in your Dockerfile — don't try to bend Trino to Railway's assumptions.**

The compatibility layer has three components, all in the same `trino-entrypoint.sh`:

1. **Pure-bash `${VAR}` substitution.** Render templates at container start. Trino's `iceberg.properties.template` (committed) becomes `iceberg.properties` (rendered, with secrets substituted from Railway Variables). Don't try to make Trino do the substitution; do it before Trino starts.

2. **Right Trino flags for the base image.** Pass `--etc-dir /etc/trino` (base image's default `/usr/lib/trino/etc` doesn't exist). Use only base-image tooling — if `apt-get` is missing, write substitution in bash, not by installing `envsubst`.

3. **Trust Railway's edge proxy.** Set `http-server.process-forwarded=true` in `config.properties`. Without this, every Railway-served request fails 406.

For each component, the structure is the same: a template file uses `${VAR}` placeholders, the entrypoint script renders them, and Trino receives a fully-resolved config file.

**Anti-pattern to avoid:** hardcoding secrets in `.properties` files, even temporarily for debugging. Cloudflare and GitHub run automated secret scanning on public repos; any committed token gets revoked within hours (you'll see `R2 HEAD: 401 Unauthorized` on previously-working credentials). Always go through Railway Variables.

**Another anti-pattern:** trusting the bootstrap log column "runtime value" to confirm substitution happened. Security-sensitive values are redacted (`[REDACTED]`) regardless of whether substitution occurred. Confirm by SSHing into the container and `cat /etc/trino/catalog/iceberg.properties` — actual token values should appear.

## Example

The pattern, illustrated with the directory structure used in `sector2-infra/services/trino/`:

```
services/trino/
├── Dockerfile                    # FROM trinodb/trino:483, COPY template/, install entrypoint
├── trino-entrypoint.sh            # bash: render *.template -> /etc/trino/catalog/, exec launcher --etc-dir /etc/trino
└── template/
    ├── trino-config/
    │   ├── config.properties.template   # http-server.process-forwarded=true + others
    │   └── log.properties.template       # DEBUG logging for ice*.trino.plugin
    ├── iceberg.properties.template      # ${R2_ACCESS_KEY}, ${R2_SECRET_KEY}, ${R2_CATALOG_TOKEN}
    └── clickhouse.properties.template    # ${CLICKHOUSE_PASSWORD}
```

The entrypoint distinguishes top-level configs (Trino's `config.properties`, `log.properties`) from catalog configs (`iceberg.properties`, `clickhouse.properties`) by directory: `template/trino-config/*.template` → `/etc/trino/<name>`, `template/*.properties.template` → `/etc/trino/catalog/<name>.properties`.

The bash substitution loop:

```bash
while IFS= read -r line; do
    while [[ "$line" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
        var="${BASH_REMATCH[1]}"
        val="${!var:-}"
        line="${line//\$\{$var\}/$val}"
    done
    printf '%s\n' "$line"
done < "$tpl" > "$out"
```

Handles `${VAR}` and `$VAR` forms. Empty values for unset vars (no error).

**When debugging a "still not working" report:**

1. SSH into the Railway container: `/tmp/railway ssh --project=X --service=Y`
2. `cat /etc/trino/catalog/iceberg.properties` — verify actual values, not `${VAR}` placeholders.
3. `printenv | grep R2_` — verify Railway Variables actually arrived in the container.
4. From outside, `curl -sS -H "X-Forwarded-For: 1.2.3.4" -u test: https://service.up.railway.app/v1/info` — verify Railway proxy header is accepted.
5. If a `SELECT` fails but `SHOW SCHEMAS` works, the catalog token is fine and S3 creds are the issue. Test S3 directly: `curl --aws-sigv4 "aws:amz:auto:s3" --user "$KEY:$SECRET" https://$ACCT.r2.cloudflarestorage.com/`.
