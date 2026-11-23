#!/usr/bin/env bash
#
# spans-test.sh — hermetic tests for e2e span emission (issue #77).
# Stubs curl and the step commands; no network, sudo or system changes.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OBS_SRC="$ROOT/setup/helpers/observability.sh"
STEPS_SRC="$ROOT/setup/helpers/steps.sh"
FAILURES=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	printf 'ok: %s\n' "$1"
}

if [[ ! -f $OBS_SRC ]]; then
	printf 'FAIL: %s missing (red state: no observability helper)\n' "$OBS_SRC" >&2
	exit 1
fi

T="$(mktemp -d)" || {
	printf 'error: mktemp failed, refusing to run\n' >&2
	exit 1
}
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stubs" "$T/records"
export STUB_DIR="$T/stubs"

# A failing curl stub proves forwarding is best effort and keeps the test
# hermetic: no collector is contacted.
cat > "$STUB_DIR/curl" <<'EOF'
#!/usr/bin/env bash
: > "$STUB_DIR/curl-called"
exit 7
EOF
chmod +x "$STUB_DIR/curl"
PATH="$STUB_DIR:$PATH"
export PATH

check_status() {
	local name=$1 expected=$2 actual=$3
	if [[ $actual -eq $expected ]]; then
		pass "$name: status $actual"
	else
		fail "$name: expected status $expected, got $actual"
	fi
}

check_has() {
	local name=$1 file=$2 pattern=$3
	if grep -Eq -- "$pattern" "$file"; then
		pass "$name: found /$pattern/"
	else
		fail "$name: missing /$pattern/"
	fi
}

check_absent() {
	local name=$1 file=$2 pattern=$3
	if grep -Eq -- "$pattern" "$file"; then
		fail "$name: unexpected /$pattern/"
	else
		pass "$name: absent /$pattern/"
	fi
}

check_file() {
	local name=$1 path=$2
	if [[ -f $path ]]; then
		pass "$name: marker $(basename "$path")"
	else
		fail "$name: missing marker $(basename "$path")"
	fi
}

check_no_file() {
	local name=$1 path=$2
	if [[ -e $path ]]; then
		fail "$name: unexpected marker $(basename "$path")"
	else
		pass "$name: no marker $(basename "$path")"
	fi
}

# Sourcing the helper alone must be silent and side-effect free.
source_out="$(bash -c 'source "$1"' _ "$OBS_SRC" 2>&1)"
check_status "source-only" 0 $?
if [[ -z $source_out ]]; then
	pass "source-only: no output"
else
	fail "source-only: unexpected output: $source_out"
fi

# Runner 1: observability uninitialized. The step runner must take its original
# path with no spans, logs or forwarding attempts.
cat > "$T/uninitialized.sh" <<EOF
#!/usr/bin/env bash
source "$OBS_SRC"
source "$STEPS_SRC"
ok_step() { printf 'step output\\n'; }
step ok_step
report_failed_steps || exit 1
EOF
bash "$T/uninitialized.sh" >"$T/uninit.out" 2>"$T/uninit.err"
check_status "uninitialized" 0 $?
check_has "uninitialized" "$T/uninit.out" 'step output'
check_has "uninitialized" "$T/uninit.out" '^\[\+[0-9]+s\] ok_step$'
check_no_file "uninitialized" "$T/records/spans.jsonl"
check_no_file "uninitialized" "$T/stubs/curl-called"

# Runner 2: initialized with an unreachable collector. Span and log must be
# durable, the wrapped status and console format unchanged, and the warning
# must be a single stderr line.
cat > "$T/initialized.sh" <<EOF
#!/usr/bin/env bash
source "$OBS_SRC"
source "$STEPS_SRC"
export OBS_RECORD_DIR="$T/records"
export OBS_PHASE=install
obs_init test-run http://127.0.0.1:1
ok_step() { printf 'step output\\n'; }
step ok_step
report_failed_steps || exit 1
EOF
bash "$T/initialized.sh" >"$T/init.out" 2>"$T/init.err"
check_status "initialized" 0 $?
check_has "initialized" "$T/init.out" 'step output'
check_has "initialized" "$T/init.out" '^\[\+[0-9]+s\] ok_step$'
check_file "initialized" "$T/records/spans.jsonl"
check_file "initialized" "$T/records/run.json"
check_has "initialized" "$T/records/run.json" '"run_id":"test-run"'
check_has "initialized" "$T/records/spans.jsonl" '"name":"ok_step"'
check_has "initialized" "$T/records/spans.jsonl" '"kind":"step"'
check_has "initialized" "$T/records/spans.jsonl" '"phase":"install"'
check_has "initialized" "$T/records/spans.jsonl" '"status":"ok"'
check_has "initialized" "$T/records/spans.jsonl" '"exit_code":0'
check_has "initialized" "$T/records/spans.jsonl" '"run_id":"test-run"'
check_has "initialized" "$T/records/spans.jsonl" '"duration_ms":[0-9]'
check_has "initialized" "$T/records/spans.jsonl" '"log_ref":"[^"]+"'
check_file "forwarding" "$T/stubs/curl-called"
check_has "initialized" "$T/init.err" 'live observability forwarding unavailable'
if [[ $(grep -c 'live observability forwarding unavailable' "$T/init.err") -eq 1 ]]; then
	pass "initialized: one forwarding warning"
else
	fail "initialized: expected exactly one forwarding warning"
fi
check_absent "initialized" "$T/init.err" '^FAILED:'

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all spans checks passed\n'
