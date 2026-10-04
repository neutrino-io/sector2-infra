#!/bin/bash
set -e

# Render config templates - substitute ${VAR} with env values.
# Trino does NOT do ${ENV} substitution in catalog .properties files itself.
# Pure bash (base image is RHEL 10, no apt-get/gettext-base).
render_template() {
    local tpl="$1"
    local out="$2"
    echo "[entrypoint] Rendering $tpl -> $out"
    while IFS= read -r line || [[ -n "$line" ]]; do
        while [[ "$line" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
            var="${BASH_REMATCH[1]}"
            val="${!var:-}"
            line="${line//\$\{$var\}/$val}"
        done
        while [[ "$line" =~ \$([A-Za-z_][A-Za-z0-9_]*) ]]; do
            var="${BASH_REMATCH[1]}"
            val="${!var:-}"
            line="${line//\$$var/$val}"
        done
        printf '%s\n' "$line"
    done < "$tpl" > "$out"
    chmod 600 "$out"
}

# Determine role. Default coordinator. Set TRINO_ROLE=worker for worker.

# Inject the shared secret from env at template render time so it
# never lands in the git-tracked template file. The secret is set as
# a shared variable on the Railway environment.
export INTERNAL_COMMUNICATION_SHARED_SECRET="${INTERNAL_COMMUNICATION_SHARED_SECRET:?internal-communication.shared-secret is required (Railway shared variable)}"

ROLE="${TRINO_ROLE:-coordinator}"
echo "[entrypoint] Starting Trino as ${ROLE}"

# 1. Trino top-level configs: /etc/trino/template/trino-config/<name>.template -> /etc/trino/<name>
# Role-specific config: <name>.template.<role> is rendered LAST and overwrites
# <name>.template. (This is intentional: the role file sets the coordinator
# vs worker flag, and we want the right one in /etc/trino/<name>.)
shopt -s nullglob
for tpl in /etc/trino/template/trino-config/*.template; do
    fname=$(basename "$tpl" .template)
    render_template "$tpl" "/etc/trino/$fname"
done
for tpl in /etc/trino/template/trino-config/*.template.${ROLE}; do
    fname=$(basename "$tpl" .template.${ROLE})
    render_template "$tpl" "/etc/trino/$fname"
done

# 2. Catalog configs: /etc/trino/template/<name>.properties.template -> /etc/trino/catalog/<name>.properties
for tpl in /etc/trino/template/*.properties.template; do
    out="/etc/trino/catalog/$(basename "$tpl" .template)"
    render_template "$tpl" "$out"
done
shopt -u nullglob


# 3. Authentication config: render /etc/trino/template/etc/<name>.template
# to /etc/trino/<name>. Trino's PASSWORD auth needs password-authenticator.properties
# at this location to know where to find the password file.
shopt -s nullglob
for tpl in /etc/trino/template/etc/*.template; do
    fname=$(basename "$tpl" .template)
    render_template "$tpl" "/etc/trino/$fname"
done
shopt -u nullglob

# Verify the role-specific config exists
if [[ -f "/etc/trino/config.properties" ]]; then
    echo "[entrypoint] Active role: $(grep '^coordinator=' /etc/trino/config.properties | head -1)"
fi

exec /usr/lib/trino/bin/launcher run --etc-dir /etc/trino
