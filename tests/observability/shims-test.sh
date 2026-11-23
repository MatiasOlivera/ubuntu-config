#!/usr/bin/env bash
#
# shims-test.sh — hermetic tests for download/package-manager child spans.
# Real binaries are stubbed through OBSERVABILITY_E2E_REAL_*; no network or sudo is used.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OBSERVABILITY_SRC="$ROOT/setup/helpers/observability.sh"
SHIM_DIR="$ROOT/setup/helpers/observability-shims"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

if [[ ! -d $SHIM_DIR ]]; then
	printf 'FAIL: %s missing (red state: no shims)\n' "$SHIM_DIR" >&2
	exit 1
fi
if ! grep -q '^observability_install_shims()' "$OBSERVABILITY_SRC" 2>/dev/null; then
	printf 'FAIL: observability_install_shims missing (red state)\n' >&2
	exit 1
fi

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stubs" "$T/records" "$T/helper"
export STUB_DIR="$T/stubs" OBSERVABILITY_RECORD_DIR="$T/records"

# Each stub records its invocation. The curl stub also bumps the network
# counter fixture so the shim observes a byte delta after the call.
cat > "$T/netdev" <<'EOF'
  Inter-|   Receive                                                |  Transmit
   face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
   eth0: 1000    0    0    0    0    0    0    0     500    0    0    0    0    0    0    0
EOF
export OBSERVABILITY_E2E_NET_DEV="$T/netdev"
cat > "$STUB_DIR/real-curl" <<'EOF'
#!/usr/bin/env bash
: > "$STUB_DIR/curl-called"
printf '%s\n' "$*" > "$STUB_DIR/curl-args"
awk '{ if ($1 ~ /eth0:/) { $2 = $2 + 4096; $10 = $10 + 1024 } print }' \
	"$OBSERVABILITY_E2E_NET_DEV" > "$OBSERVABILITY_E2E_NET_DEV.next"
mv "$OBSERVABILITY_E2E_NET_DEV.next" "$OBSERVABILITY_E2E_NET_DEV"
exit 0
EOF
cat > "$STUB_DIR/real-sudo" <<EOF
#!/usr/bin/env bash
: > "$STUB_DIR/sudo-called"
printf '%s\n' "\$*" > "$STUB_DIR/sudo-args"
exit 0
EOF
chmod +x "$STUB_DIR/real-curl" "$STUB_DIR/real-sudo"

export OBSERVABILITY_E2E_REAL_CURL="$STUB_DIR/real-curl"
export OBSERVABILITY_E2E_REAL_WGET="$STUB_DIR/real-curl"
export OBSERVABILITY_E2E_REAL_GIT="$STUB_DIR/real-curl"
export OBSERVABILITY_E2E_REAL_SUDO="$STUB_DIR/real-sudo"
export OBSERVABILITY_E2E_HELPER="$OBSERVABILITY_SRC"
export OBSERVABILITY_PHASE=install

cat > "$T/run.sh" <<EOF
#!/usr/bin/env bash
source "$OBSERVABILITY_SRC"
source "$ROOT/setup/helpers/steps.sh"
observability_init shims-run http://127.0.0.1:1
# keepalive must not produce a child span
sudo -n true
fake_app() {
	curl -fsSL https://example.invalid/app.deb -o /tmp/app.deb
	sudo apt install -y example
}
step fake_app
report_failed_steps || exit 1
EOF

bash "$T/run.sh" > "$T/run.out" 2> "$T/run.err"
status=$?
if [[ $status -eq 0 ]]; then pass "run: status 0"; else fail "run: status $status"; fi
[[ -f $STUB_DIR/curl-called ]] && pass "curl: real binary called" || fail "curl: real binary never called"
[[ -f $STUB_DIR/sudo-called ]] && pass "sudo: real binary called" || fail "sudo: real binary never called"

SPANS="$T/records/spans.jsonl"
if [[ -f $SPANS ]]; then
	pass "spans: record exists"
else
	fail "spans: record missing"
	exit 1
fi

check_has() {
	local name=$1 pattern=$2
	if grep -Eq -- "$pattern" "$SPANS"; then pass "$name"; else fail "$name"; fi
}

check_has "download span" '"kind":"download"'
check_has "download name is the command" '"name":"curl"'
check_has "download host attribute" '"key":"url_host","value":{"stringValue":"example.invalid"}'
check_has "package-manager span" '"kind":"package-manager"'
check_has "package-manager name is apt" '"name":"apt"'
check_has "network byte delta" '"key":"bytes_net_approx","value":{"intValue":[1-9][0-9]*}'
check_has "bundled label" '"key":"download_and_install","value":{"stringValue":"bundled"}'

step_id=$(grep '"kind":"step"' "$SPANS" | sed -n 's/.*"trace_id":"[^"]*","span_id":"\([0-9a-f]*\)".*/\1/p' | head -n 1)
if [[ -n $step_id ]] && grep -q "\"parent_span_id\":\"$step_id\"" "$SPANS"; then
	pass "child spans point at the step span"
else
	fail "child spans do not point at the step span"
fi

if grep -q '"name":"true"' "$SPANS" || grep -q '"name":"sudo"' "$SPANS"; then
	fail "keepalive produced a child span"
else
	pass "keepalive excluded"
fi

if [[ $(grep -c '"kind":"download"' "$SPANS") -eq 1 ]]; then
	pass "one download span per curl call"
else
	fail "expected exactly one download span"
fi

if [[ -f $T/records/shims/curl ]] && [[ -x $T/records/shims/curl ]]; then
	pass "shims installed and executable"
else
	fail "shims not installed"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all shim checks passed\n'
