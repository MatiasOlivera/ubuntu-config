#!/usr/bin/env bash
#
# wrapper-test.sh — hermetic tests for the e2e observability host wrapper.
# multipass and curl are stubbed; no VM, network or system changes.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WRAPPER="$ROOT/tests/e2e-observability.sh"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

if [[ ! -f $WRAPPER ]]; then
	printf 'FAIL: %s missing (red state: no host wrapper)\n' "$WRAPPER" >&2
	exit 1
fi

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stubs" "$T/fixture" "$T/root" "$T/xdg"
export STUB_DIR="$T/stubs"

cat > "$STUB_DIR/curl" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
cat > "$STUB_DIR/multipass" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/multipass-calls"
if [[ $1 == transfer ]]; then
	cp "$FIXTURE_ARCHIVE" "$3"
fi
exit 0
EOF
chmod +x "$STUB_DIR/curl" "$STUB_DIR/multipass"
PATH="$STUB_DIR:$PATH"
export PATH

printf '{"kind":"step","name":"install_uv","status":"ok","duration_ms":42}\n' > "$T/fixture/spans.jsonl"
tar -czf "$T/fixture.tgz" -C "$T/fixture" spans.jsonl
export FIXTURE_ARCHIVE="$T/fixture.tgz"

run_wrapper() {
	local out=$1
	shift
	E2E_OBSERVABILITY_DIR="$T/root" OBS_VM_NAME=fake-vm \
		OBS_VM_RECORD_DIR=/tmp/vm-records OBS_COLLECTOR=http://127.0.0.1:1 \
		bash "$WRAPPER" "$@" > "$out" 2> "$out.err"
}

run_wrapper "$T/success.out" install bash -c 'printf "hello from vm\n"'
status=$?
if [[ $status -eq 0 ]]; then pass "success: status 0"; else fail "success: status $status"; fi

records=$(sed -n 's/^records: //p' "$T/success.out" | sed -n 1p)
log=$(sed -n 's/^log: //p' "$T/success.out" | sed -n 1p)
if [[ $records == "$T/root"/* ]]; then pass "success: records under E2E_OBSERVABILITY_DIR"; else fail "success: bad records path '$records'"; fi
if [[ -n $log && -f $log ]]; then pass "success: transcript written"; else fail "success: transcript missing"; fi
if grep -q 'hello from vm' "$log" 2>/dev/null; then pass "success: output teed live"; else fail "success: output not teed"; fi
if [[ -f $records/spans.jsonl ]]; then pass "success: VM records copied out"; else fail "success: records not copied"; fi
if grep -q '^label' "$records/summary.tsv" 2>/dev/null; then pass "success: summary written"; else fail "success: summary missing"; fi
if grep -q 'install_uv' "$records/summary.tsv" 2>/dev/null; then pass "success: summary names the app"; else fail "success: summary has no app row"; fi

run_wrapper "$T/failure.out" install bash -c 'printf "boom\n" >&2; exit 3'
status=$?
if [[ $status -eq 3 ]]; then pass "failure: status preserved"; else fail "failure: expected 3, got $status"; fi
if grep -q '^exit: 3$' "$T/failure.out"; then pass "failure: exit reported"; else fail "failure: exit not reported"; fi
if grep -q -- '--- tail ---' "$T/failure.out"; then pass "failure: tail reported after completion"; else fail "failure: tail missing"; fi

if grep -q 'live observability collector unreachable' "$T/success.out.err"; then
	pass "collector: best-effort warning"
else
	fail "collector: no warning on unreachable endpoint"
fi

E2E_OBSERVABILITY_DIR="$T/root2" XDG_DATA_HOME="$T/xdg" OBS_VM_NAME=fake-vm \
	OBS_VM_RECORD_DIR=/tmp/vm-records OBS_COLLECTOR= \
	bash -c 'unset E2E_OBSERVABILITY_DIR; exec bash "$0" install true' "$WRAPPER" > "$T/xdg.out" 2>&1
xdg_records=$(sed -n 's/^records: //p' "$T/xdg.out" | sed -n 1p)
if [[ $xdg_records == "$T/xdg/ubuntu-config/observability/"* ]]; then
	pass "xdg: fallback root honored"
else
	fail "xdg: bad fallback path '$xdg_records'"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all wrapper checks passed\n'
