#!/bin/bash
set -e
# Render catalog templates with envsubst (Railway Variables -> ${VAR} substitution).
# Trino does NOT do ${ENV} substitution in catalog files itself.
for tpl in /etc/trino/template/*.properties.template; do
    [ -f "$tpl" ] || continue
    out="/etc/trino/catalog/$(basename "$tpl" .template)"
    echo "[entrypoint] Rendering $tpl -> $out"
    envsubst < "$tpl" > "$out"
done

# Hand off to the base image's Trino launcher.
exec /usr/lib/trino/bin/launcher run
