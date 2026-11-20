#!/usr/bin/env bash
#
# steps-test.sh — functional tests for the shared setup step runner (issue #30).
# Hermetic: sources the helper and drives generated runners with stubbed steps;
# no sudo, network, keyring, or system changes. Fail-closed.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="$ROOT/setup/helpers/steps.sh"
export SRC
FAILURES=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	printf 'ok: %s\n' "$1"
}

T="$(mktemp -d)" || {
	printf 'error: mktemp failed, refusing to run\n' >&2
	exit 1
}
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stubs"
export STUB_DIR="$T/stubs"

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

reset_markers() {
	rm -f "$STUB_DIR"/*
}

# Every runner sources the real helper and defines stub steps that only write
# a marker (and return a chosen status). The runner body is supplied per case.
cat > "$T/preamble.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck disable=SC1090 # SRC is set by the harness
source "$SRC"
ok1() { : > "$STUB_DIR/ok1"; }
ok4() { : > "$STUB_DIR/ok4"; }
bad2() { : > "$STUB_DIR/bad2"; return 2; }
bad3() { : > "$STUB_DIR/bad3"; return 3; }
advisory_bad() { : > "$STUB_DIR/advisory_bad"; return 9; }
argcmd() { printf '%s\n' "${1:-}" > "$STUB_DIR/argcmd"; [[ ${1:-} == expected ]]; }
EOF

runner() {
	local name=$1
	shift
	{
		cat "$T/preamble.sh"
		printf '%s\n' "$@"
	} > "$T/$name.sh"
}

# Sourcing the helper alone must not run anything or print anything.
source_out="$(bash -c 'source "$1"' _ "$SRC" 2>&1)"
check_status "source-only" 0 $?
if [[ -z $source_out ]]; then
	pass "source-only: no output"
else
	fail "source-only: unexpected output: $source_out"
fi

# Clean run: all steps timed, success report, exit 0.
reset_markers
runner clean \
	'step ok1' \
	'step ok4' \
	'report_failed_steps || exit 1'
bash "$T/clean.sh" >"$T/clean.out" 2>"$T/clean.err"
check_status "clean" 0 $?
check_has "clean" "$T/clean.out" '^\[\+[0-9]+s\] ok1$'
check_has "clean" "$T/clean.out" '^\[\+[0-9]+s\] ok4$'
check_absent "clean" "$T/clean.err" 'FAILED:'
check_absent "clean" "$T/clean.err" 'step\(s\) failed'
check_file "clean" "$STUB_DIR/ok1"
check_file "clean" "$STUB_DIR/ok4"

# Accumulate: two failures named, later step still runs, summary with count,
# exit 1.
reset_markers
runner accumulate \
	'step ok1' \
	'step bad2' \
	'step bad3' \
	'step ok4' \
	'report_failed_steps || exit 1'
bash "$T/accumulate.sh" >"$T/accumulate.out" 2>"$T/accumulate.err"
check_status "accumulate" 1 $?
check_has "accumulate" "$T/accumulate.err" 'FAILED: bad2 \(status 2\)'
check_has "accumulate" "$T/accumulate.err" 'FAILED: bad3 \(status 3\)'
check_has "accumulate" "$T/accumulate.err" '2 step\(s\) failed: bad2 bad3'
check_absent "accumulate" "$T/accumulate.out" 'FAILED:'
check_file "accumulate" "$STUB_DIR/bad2"
check_file "accumulate" "$STUB_DIR/bad3"
check_file "accumulate" "$STUB_DIR/ok4"

# Fail fast: stop at the first failing step, exit with that step's status,
# no end summary and no later step.
reset_markers
runner failfast \
	'export FAIL_FAST=1' \
	'step ok1' \
	'step bad2' \
	'step ok4' \
	'report_failed_steps || exit 1'
bash "$T/failfast.sh" >"$T/failfast.out" 2>"$T/failfast.err"
check_status "failfast" 2 $?
check_has "failfast" "$T/failfast.err" 'FAILED: bad2 \(status 2\)'
check_absent "failfast" "$T/failfast.err" 'step\(s\) failed'
check_file "failfast" "$STUB_DIR/ok1"
check_file "failfast" "$STUB_DIR/bad2"
check_no_file "failfast" "$STUB_DIR/ok4"

# Advisory: timed and executed, but never counted and never fails fast.
reset_markers
runner advisory \
	'export FAIL_FAST=1' \
	'step ok1' \
	'advisory_step advisory_bad' \
	'step ok4' \
	'report_failed_steps || exit 1'
bash "$T/advisory.sh" >"$T/advisory.out" 2>"$T/advisory.err"
check_status "advisory" 0 $?
check_has "advisory" "$T/advisory.out" '^\[\+[0-9]+s\] advisory_bad$'
check_absent "advisory" "$T/advisory.err" 'FAILED:'
check_absent "advisory" "$T/advisory.err" 'step\(s\) failed'
check_file "advisory" "$STUB_DIR/advisory_bad"
check_file "advisory" "$STUB_DIR/ok4"

# Labelled command with arguments (existing multi-argument step calls).
reset_markers
runner args \
	'step "arg cmd" argcmd expected' \
	'report_failed_steps || exit 1'
bash "$T/args.sh" >"$T/args.out" 2>"$T/args.err"
check_status "args" 0 $?
check_has "args" "$T/args.out" '^\[\+[0-9]+s\] arg cmd$'
if [[ -f $STUB_DIR/argcmd ]] && [[ $(<"$STUB_DIR/argcmd") == expected ]]; then
	pass "args: command received its argument"
else
	fail "args: command argument was not forwarded"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all checks passed\n'
