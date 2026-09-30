#!/usr/bin/env bash
# Scheduling behaviour test: min_interval_minutes debounce, --force, lock skip,
# stale warning. Builds throwaway cookie DBs from a schema in a temp dir; never
# touches a real Chrome profile. Run: tests/debounce-test.sh
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/chrome/Src" "$T/chrome/T1" "$T/chrome/T2"

python3 - "$T/chrome" <<'EOF'
import sqlite3, sys
schema = """CREATE TABLE cookies(creation_utc INTEGER NOT NULL,host_key TEXT NOT NULL,
top_frame_site_key TEXT NOT NULL,name TEXT NOT NULL,value TEXT NOT NULL,encrypted_value BLOB NOT NULL,
path TEXT NOT NULL,expires_utc INTEGER NOT NULL,is_secure INTEGER NOT NULL,is_httponly INTEGER NOT NULL,
last_access_utc INTEGER NOT NULL,has_expires INTEGER NOT NULL,is_persistent INTEGER NOT NULL,
priority INTEGER NOT NULL,samesite INTEGER NOT NULL,source_scheme INTEGER NOT NULL,
source_port INTEGER NOT NULL,last_update_utc INTEGER NOT NULL,source_type INTEGER NOT NULL,
has_cross_site_ancestor INTEGER NOT NULL)"""
for d in ("Src", "T1", "T2"):
    c = sqlite3.connect(f"{sys.argv[1]}/{d}/Cookies"); c.execute(schema)
    if d == "Src":
        c.execute("INSERT INTO cookies VALUES (1,'.example.test','','sid','',x'00','/',9,1,1,1,1,1,1,-1,2,443,1,0,0)")
        c.execute("INSERT INTO cookies VALUES (1,'.claude.ai','','sk','',x'00','/',9,1,1,1,1,1,1,-1,2,443,1,0,0)")
    c.commit(); c.close()
EOF

cat > "$T/cfg.json" <<'EOF'
{"source":"Src","targets":["T1","T2","T3"],"exclude":[],"min_interval_minutes":60,"stale_days":3,"keep_backups":2}
EOF
G=(python3 "$HERE/bin/chrome-cookie-graft" -c "$T/cfg.json" --chrome-dir "$T/chrome" --state "$T/state.json")
age() { python3 -c "import json,sys;p=sys.argv[1];s=json.load(open(p));json.dump({k:v-float(sys.argv[2]) for k,v in s.items()},open(p,'w'))" "$T/state.json" "$1"; }
fail=0; check() { if grep -q -- "$2" <<<"$3"; then echo "PASS $1"; else echo "FAIL $1 (wanted: $2)"; echo "$3"; fail=1; fi; }

o=$("${G[@]}" 2>&1);           check "first run grafts T1"        "T1: wrote 1 rows" "$o"
check "protect holds claude.ai"  "1 cookies / 1 hosts" "$o"
check "missing target reported"  "T3: SKIP — no Cookies DB" "$o"
o=$("${G[@]}" 2>&1);           check "second run debounced"       "nothing eligible (grafted <60m ago: T1, T2" "$o"
o=$("${G[@]}" --force 2>&1);   check "--force bypasses debounce"  "T2: wrote 0 rows" "$o"
age 7200
o=$( exec 9<"$T/chrome/T1/Cookies"; "${G[@]}" 2>&1 ); check "open target skipped" "T1: SKIP — open in Chrome" "$o"
check "other target grafts"       "T2: wrote" "$o"
age $((4*86400))
o=$( exec 9<"$T/chrome/T1/Cookies"; exec 8<"$T/chrome/T2/Cookies"; "${G[@]}" 2>&1 ); rc=$?
check "all open → nothing eligible" "open in Chrome: T1, T2" "$o"
check "stale warning"             "WARNING: T1 last grafted" "$o"
[ "$rc" = 1 ] && echo "PASS stale exit code 1" || { echo "FAIL stale exit code ($rc)"; fail=1; }
exit $fail
