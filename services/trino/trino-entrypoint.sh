#!/bin/bash
set -e
# Render catalog templates by substituting ${VAR} with env values.
# Trino does NOT do ${ENV} substitution in catalog .properties files itself.
# We use pure bash (no gettext/envsubst needed; base image is RHEL 10).
for tpl in /etc/trino/template/*.properties.template; do
    [ -f "$tpl" ] || continue
    out="/etc/trino/catalog/$(basename "$tpl" .template)"
    echo "[entrypoint] Rendering $tpl -> $out"
    while IFS= read -r line; do
        # Expand ${VAR} using env values
        while [[ "$line" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
            var="${BASH_REMATCH[1]}"
            val="${!var:-}"
            line="${line//\$\{$var\}/$val}"
        done
        # Expand $VAR (no braces) using env values
        while [[ "$line" =~ \$([A-Za-z_][A-Za-z0-9_]*) ]]; do
            var="${BASH_REMATCH[1]}"
            val="${!var:-}"
            line="${line//\$$var/$val}"
        done
        printf '%s\n' "$line"
    done < "$tpl" > "$out"
    chmod 600 "$out"
done

# Hand off to Trino with --etc-dir /etc/trino (where rendered configs live).
exec /usr/lib/trino/bin/launcher run --etc-dir /etc/trino
