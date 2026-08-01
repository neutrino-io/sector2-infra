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

# 1. Trino top-level configs: /etc/trino/template/trino-config/<name>.template -> /etc/trino/<name>
shopt -s nullglob
for tpl in /etc/trino/template/trino-config/*.template; do
    fname=$(basename "$tpl" .template)
    render_template "$tpl" "/etc/trino/$fname"
done

# 2. Catalog configs: /etc/trino/template/<name>.properties.template -> /etc/trino/catalog/<name>.properties
for tpl in /etc/trino/template/*.properties.template; do
    out="/etc/trino/catalog/$(basename "$tpl" .template)"
    render_template "$tpl" "$out"
done
shopt -u nullglob

exec /usr/lib/trino/bin/launcher run --etc-dir /etc/trino
