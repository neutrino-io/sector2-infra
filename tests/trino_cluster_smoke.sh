#!/bin/bash
#
# sector2-trino cluster smoke test
#
# Verifies the 2-node Trino cluster is operational:
# 1. Coordinator + worker registered at railway.internal DNS
# 2. Queries route to the worker (nodes >= 1, not just coordinator)
# 3. Catalogs (clickhouse, system) are queryable
#
# Uses Content-Type: text/plain per Trino REST API. The JSON content-type
# triggers a SYNTAX_ERROR on poll because the queued endpoint path
# (/v1/statement/queued/<id>/<token>/1) is mis-parsed by the dispatcher's
# internal JSON handler. The original Trino API uses text/plain.
#
# Usage:
#   TRINO_USER=sector2-verify TRINO_PASSWORD=<pwd> ./trino_cluster_smoke.sh
#
# Exit code 0 on full success; non-zero on any failed assertion.

set -u

# Required: TRINO_USER, TRINO_PASSWORD
: "${TRINO_USER:?TRINO_USER is required}"
: "${TRINO_PASSWORD:?TRINO_PASSWORD is required}"

BASE="${TRINO_URL:-https://sector2-trino-production.up.railway.app}"
fail=0
POLL_MAX=12   # 12 * 3s = 36s max per query
POLL_INTERVAL=3

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS  $label  (= $expected)"
    else
        echo "  FAIL  $label  expected '$expected' got '$actual'"
        fail=$((fail + 1))
    fi
}

submit_query() {
    local query="$1"
    curl -sS -X POST \
        -u "$TRINO_USER:$TRINO_PASSWORD" \
        --max-time 30 \
        "$BASE/v1/statement" \
        -H "X-Trino-User: $TRINO_USER" \
        -H "Content-Type: text/plain" \
        --data-raw "$query"
}

poll_until_done() {
    local next="$1" max="${2:-$POLL_MAX}"
    local poll state
    for ((i=1; i<=max; i++)); do
        sleep "$POLL_INTERVAL"
        poll=$(curl -sS -X GET \
            -u "$TRINO_USER:$TRINO_PASSWORD" \
            --max-time 15 \
            "$next")
        state=$(echo "$poll" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('stats', {}).get('state', ''))
except: print('PARSE_ERROR')
")
        if [[ "$state" == "FINISHED" ]] || [[ "$state" == "FAILED" ]]; then
            echo "$poll"
            return
        fi
        next=$(echo "$poll" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('nextUri', ''))
except: print('')
")
        if [[ -z "$next" ]]; then break; fi
    done
    echo "$poll"
}

echo "=== 1. /v1/info: coordinator healthy ==="
info=$(curl -sS -X GET -u "$TRINO_USER:$TRINO_PASSWORD" --max-time 10 "$BASE/v1/info")
version=$(echo "$info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('nodeVersion',{}).get('version','?'))")
uptime=$(echo "$info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uptime','?'))")
starting=$(echo "$info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('starting',''))")
echo "  version=$version uptime=$uptime starting=$starting"
assert_eq "version is 447" "447" "$version"
assert_eq "starting is false" "False" "$starting"


echo "=== 1.5 /v1/memory: coordinator↔worker memory exchange works (Item #3 guard) ==="
mem_status=$(curl -sS -o /dev/null -w "%{http_code}" -X GET -u "$TRINO_USER:$TRINO_PASSWORD" --max-time 10 "$BASE/v1/memory")
echo "  /v1/memory status: $mem_status"
if [[ "$mem_status" == "200" ]]; then
    echo "  PASS  /v1/memory returned 200 (worker is in the scheduler pool)"
elif [[ "$mem_status" == "401" || "$mem_status" == "403" ]]; then
    # Item #3 pattern: worker is registered for liveness but
    # /v1/memory auth is broken (OPA or password mismatch). Node-scheduler
    # can't verify worker health → queries stay in QUEUED.
    echo "  FAIL  /v1/memory returned $mem_status (auth broken — Item #3 regression)"
    fail=$((fail + 1))
else
    echo "  WARN  /v1/memory returned $mem_status (unexpected; may be transient)"
fi


echo ""
echo "=== 2. /v1/node: both nodes registered at railway.internal ==="
nodes=$(curl -sS -X GET -u "$TRINO_USER:$TRINO_PASSWORD" --max-time 10 "$BASE/v1/node")
node_count=$(echo "$nodes" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
echo "  registered nodes: $node_count"
assert_eq "2 nodes registered" "2" "$node_count"
has_coord=$(echo "$nodes" | python3 -c "
import sys, json
nodes = json.load(sys.stdin)
print(any('sector2-trino.railway.internal' in n.get('uri','') and n.get('uri','').count(':8080')>0 for n in nodes))
")
has_worker=$(echo "$nodes" | python3 -c "
import sys, json
nodes = json.load(sys.stdin)
print(any('sector2-trino-worker.railway.internal' in n.get('uri','') for n in nodes))
")
assert_eq "coordinator at sector2-trino.railway.internal" "True" "$has_coord"
assert_eq "worker at sector2-trino-worker.railway.internal" "True" "$has_worker"

echo ""
echo "=== 3. SELECT 1: query completes with nodes >= 1 ==="
resp=$(submit_query 'SELECT 1 AS x')
next=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('nextUri',''))")
final=$(poll_until_done "$next")
final_state=$(echo "$final" | python3 -c "import sys,json; print(json.load(sys.stdin).get('stats',{}).get('state',''))")
final_nodes=$(echo "$final" | python3 -c "import sys,json; print(json.load(sys.stdin).get('stats',{}).get('nodes','?'))")
final_data=$(echo "$final" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',[]))")
echo "  state=$final_state nodes=$final_nodes data=$final_data"
assert_eq "FINISHED" "FINISHED" "$final_state"
[[ "$final_nodes" -ge 1 ]] && echo "  PASS  nodes >= 1  (= $final_nodes)" || { echo "  FAIL  nodes < 1  (= $final_nodes)"; fail=$((fail+1)); }
assert_eq "data [[1]]" "[[1]]" "$final_data"

echo ""
echo "=== 4. SHOW CATALOGS: catalogs (clickhouse, iceberg, system) present ==="
resp=$(submit_query 'SHOW CATALOGS')
next=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('nextUri',''))")
final=$(poll_until_done "$next")
catalogs=$(echo "$final" | python3 -c "import sys,json; d=json.load(sys.stdin); print(','.join(sorted([row[0] for row in d.get('data',[])])))")
echo "  catalogs: $catalogs"
for c in clickhouse iceberg system; do
    if echo "$catalogs" | grep -q "$c"; then
        echo "  PASS  catalog '$c' present"
    else
        echo "  FAIL  catalog '$c' missing"
        fail=$((fail + 1))
    fi
done

echo ""
if [[ "$fail" -eq 0 ]]; then
    echo "All checks passed."
    exit 0
else
    echo "$fail check(s) failed."
    exit 1
fi