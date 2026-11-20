#!/usr/bin/env bash
#
# run-with-logging-test.sh — black-box tests for tests/run-with-logging.sh.
# Hermetic: logs go to a fixture TMPDIR, no system mutation. Fail-closed.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/tests/run-with-logging.sh"
FAILURES=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	printf 'ok: %s\n' "$1"
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# 1. success: status 0, both streams in the log, path + tail reported.
out="$(TMPDIR="$T" bash "$SRC" e2e bash -c 'printf "first\n"; printf "problem\n" >&2; printf "last\n"')"
rc=$?
log="$(printf '%s\n' "$out" | sed -n 's/^log: //p' | head -n 1)"

if [[ $rc -eq 0 && -f $log ]]; then
	pass "success: exit 0 and log written"
else
	fail "success: expected exit 0 and a log file (rc=$rc, log=$log)"
fi

if [[ $log == "$T"/ubuntu-config-e2e-*.log ]] &&
	[[ $(basename "$log") =~ ^ubuntu-config-e2e-[0-9]{8}-[0-9]{6}-[0-9]+\.log$ ]]; then
	pass "log path is label + timestamp + pid under TMPDIR"
else
	fail "log path is label + timestamp + pid under TMPDIR (log=$log)"
fi

if grep -q '^first$' "$log" && grep -q '^problem$' "$log" && grep -q '^last$' "$log"; then
	pass "stdout and stderr are both logged"
else
	fail "stdout and stderr are both logged (log=$log)"
fi

if [[ $(printf '%s\n' "$out" | grep -c '^log: ') -eq 2 ]] &&
	[[ $out == *"exit: 0"* && $out == *"--- tail ---"* && $out == *"last"* ]]; then
	pass "path is printed twice (start + end) with status and tail"
else
	fail "path is printed twice (start + end) with status and tail (out=$out)"
fi

# 2. failure: the command's status survives the pipeline, stderr is logged.
out="$(TMPDIR="$T" bash "$SRC" broken bash -c 'printf "bad\n" >&2; exit 7' 2>&1)"
rc=$?
log="$(printf '%s\n' "$out" | sed -n 's/^log: //p' | head -n 1)"

if [[ $rc -eq 7 && $out == *"exit: 7"* ]] && grep -q '^bad$' "$log"; then
	pass "failure: command exit status is preserved and stderr logged"
else
	fail "failure: expected exit 7 and logged stderr (rc=$rc, out=$out)"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all run-with-logging checks passed\n'
