#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT
cp -a "$ROOT/." "$TMPDIR_TEST/NetSleuth/"
TEST_ROOT="$TMPDIR_TEST/NetSleuth"
SLEUTH="$TEST_ROOT/bin/sleuth"
mkdir -p "$TMPDIR_TEST/mockbin"
cat >"$TMPDIR_TEST/mockbin/ip" <<'MOCK'
#!/usr/bin/env bash
printf 'default dev tun0 scope link\n'
MOCK
cat >"$TMPDIR_TEST/mockbin/ping" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
cat >"$TMPDIR_TEST/mockbin/curl" <<'MOCK'
#!/usr/bin/env bash
printf '000|0.000'
exit 7
MOCK
cat >"$TMPDIR_TEST/mockbin/ss" <<'MOCK'
#!/usr/bin/env bash
printf 'Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port\n'
MOCK
chmod +x "$TMPDIR_TEST/mockbin/"*
export PATH="$TMPDIR_TEST/mockbin:$PATH"
pass=0; fail=0
check() {
  local name="$1"; shift
  if "$@"; then printf 'PASS: %s\n' "$name"; ((pass+=1)); else printf 'FAIL: %s\n' "$name"; ((fail+=1)); fi
}
run_status() {
  local expected="$1"; shift
  local actual=0
  "$@" >"$TMPDIR_TEST/output.txt" 2>&1 || actual=$?
  [[ "$actual" -eq "$expected" ]]
}
contains() { grep -Fq -- "$2" "$1"; }
json_has() {
  local json="$1" expression="$2"
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); expr=sys.argv[2]; print(eval(expr, {"__builtins__":{}}, {"d":d}))' "$json" "$expression" >/dev/null
}
check 'missing target returns status 2' run_status 2 "$SLEUTH"
"$SLEUTH" 'google.com;touch /tmp/should-not-exist' >"$TMPDIR_TEST/output.txt" 2>&1 || true
check 'injection-like target rejected' contains "$TMPDIR_TEST/output.txt" 'Invalid target'
check 'invalid port rejected' run_status 2 "$SLEUTH" example.com -p 70000
check 'port zero rejected' run_status 2 "$SLEUTH" example.com -p 0
check 'invalid dotted-quad target rejected' run_status 2 "$SLEUTH" 999.999.999.999
check 'URL port zero rejected' run_status 2 "$SLEUTH" http://127.0.0.1:0
check 'malformed IPv4 CIDR rejected' run_status 2 "$SLEUTH" -c 999.1.1.1/24
check 'IPv6 CIDR rejected' run_status 2 "$SLEUTH" -c ::1/64
check 'CIDR requires explicit prefix' run_status 2 "$SLEUTH" -c 10.0.0.5
"$SLEUTH" -c 192.168.1.50/24 >"$TMPDIR_TEST/cidr.txt"
check '/24 network address correct' contains "$TMPDIR_TEST/cidr.txt" '192.168.1.0'
check '/24 broadcast address correct' contains "$TMPDIR_TEST/cidr.txt" 'Broadcast Address: 192.168.1.255'
check '/24 usable host count correct' contains "$TMPDIR_TEST/cidr.txt" '254'
check 'CIDR label values align' python3 -c 'import sys; p=open(sys.argv[1]).read().splitlines(); assert len({x.index(x.split(":",1)[1].lstrip()) for x in p}) == 1' "$TMPDIR_TEST/cidr.txt"
"$SLEUTH" --json -c 192.168.1.50/24 >"$TMPDIR_TEST/cidr.json"
check '--json -c emits valid JSON' python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["network_address"] == "192.168.1.0"' "$TMPDIR_TEST/cidr.json"
check 'TLS helper validates bad port argument' run_status 2 python3 "$TEST_ROOT/libexec/tls_inspector.py" localhost nope
ln -s "$SLEUTH" "$TMPDIR_TEST/sleuth-link"
link_json="$("$TMPDIR_TEST/sleuth-link" --json 127.0.0.1 -p 00443 2>/dev/null || true)"
check 'leading-zero port is normalized and port 443 selects HTTPS' python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); assert d["port"] == 443 and d["scheme"] == "https"' <<< "$link_json"
check 'symlinked command finds TLS helper' python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); assert d["tls_error"] != "TLS helper returned no output" and d["tls_status"] == "error"' <<< "$link_json"
check 'JSON field types are stable' python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); assert isinstance(d["http_time_seconds"],float); assert d["http_code"] is None or isinstance(d["http_code"],int); assert d["gateway_reachable"] is None or isinstance(d["gateway_reachable"],bool); assert d["dns_public_resolved"] is None or isinstance(d["dns_public_resolved"],bool); assert d["gateway_ip"] is None and d["gateway_interface"] == "tun0"' <<< "$link_json"
"$SLEUTH" --json 127.0.0.1 -p 1 --save-report >"$TMPDIR_TEST/report-json.json" 2>/dev/null || true
check '--json remains valid with --save-report' python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMPDIR_TEST/report-json.json"
report_path="$(find "$TEST_ROOT/reports" -maxdepth 1 -type f -name 'sleuth_*.txt' -print -quit)"
check '--save-report writes a readable text report' bash -c 'test -n "$1" && grep -q -- "--- Gateway ---" "$1" && grep -q "without an explicit gateway" "$1" && ! head -n 1 "$1" | grep -q "^{"' _ "$report_path"
check 'installer checks timeout and getent' bash -c 'grep -q "timeout getent" "$1"' _ "$TEST_ROOT/install.sh"
printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
