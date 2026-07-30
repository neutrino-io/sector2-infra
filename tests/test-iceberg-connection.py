#!/usr/bin/env python3
"""
Verify PyIceberg can connect to R2 Data Catalog.
Tests:
  1. Catalog connection (token + URI valid)
  2. List namespaces
  3. List tables in electoral namespace
  4. Scan election_result table (count rows)
  5. Time-travel query (verify snapshot retention)

Requires: pip install pyiceberg pyarrow
"""
import os
import sys
from datetime import datetime

try:
    from pyiceberg.catalog.rest import RestCatalog
except ImportError:
    print("ERROR: pyiceberg not installed. Run: pip install pyiceberg pyarrow")
    sys.exit(1)

ACCOUNT = "203a605533f37eb35da80dcf03a7bed6"
BUCKET = "gyhc40sdz8-ivj8v3841x-bronze-storage"
URI = f"https://catalog.cloudflarestorage.com/{ACCOUNT}/{BUCKET}"
WAREHOUSE = f"{ACCOUNT}_{BUCKET}"

# Get token from env
TOKEN = os.environ.get("R2_CATALOG_TOKEN")
if not TOKEN:
    print("ERROR: R2_CATALOG_TOKEN env var not set")
    sys.exit(1)

print("=" * 60)
print("PyIceberg → R2 Data Catalog test")
print("=" * 60)
print(f"URI: {URI}")
print(f"Warehouse: {WAREHOUSE}")
print(f"Token: {TOKEN[:20]}...")
print()

passes = 0
fails = 0

def check(name, condition, detail=""):
    global passes, fails
    if condition:
        print(f"  ✓ {name}{(': ' + detail) if detail else ''}")
        passes += 1
    else:
        print(f"  ✗ {name}{(': ' + detail) if detail else ''}")
        fails += 1

# 1. Connect
try:
    catalog = RestCatalog(name='sector2', warehouse=WAREHOUSE, uri=URI, token=TOKEN)
    check("Connect to catalog", True)
except Exception as e:
    check("Connect to catalog", False, str(e)[:80])
    sys.exit(1)

# 2. List namespaces
try:
    namespaces = catalog.list_namespaces()
    check("List namespaces", True, f"{len(namespaces)} found: {[n[0] for n in namespaces[:5]]}")
except Exception as e:
    check("List namespaces", False, str(e)[:80])
    sys.exit(1)

# 3. List tables in electoral
try:
    if ('electoral',) in namespaces:
        table_ids = catalog.list_tables('electoral')
        check("List tables in electoral", True, f"{len(table_ids)} tables: {[t[1] for t in table_ids[:5]]}")
    else:
        check("electoral namespace exists", False, "namespace not found")
except Exception as e:
    check("List tables", False, str(e)[:80])

# 4. Scan election_result
try:
    table = catalog.load_table('electoral.election_result')
    count = table.scan().to_arrow().num_rows
    check("Scan election_result", count == 53687, f"{count:,} rows (expected 53,687)")
except Exception as e:
    check("Scan election_result", False, str(e)[:80])

# 5. Time-travel
try:
    snapshots = list(table.metadata.snapshots)
    check("Time-travel snapshots", len(snapshots) > 0, f"{len(snapshots)} snapshots")

    if snapshots:
        latest = snapshots[-1]
        ts = datetime.fromtimestamp(latest.timestamp_ms / 1000)
        print(f"\n    Latest snapshot:")
        print(f"      ID: {latest.snapshot_id}")
        print(f"      Timestamp: {ts.isoformat()}")
        print(f"      Operation: {latest.summary.get('operation', '?')}")
except Exception as e:
    check("Time-travel", False, str(e)[:80])

print()
print("=" * 60)
print(f"Results: {passes} passed, {fails} failed")
print("=" * 60)
sys.exit(0 if fails == 0 else 1)