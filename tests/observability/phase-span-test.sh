#!/usr/bin/env bash
#
# phase-span-test.sh — hermetic tests for one root span per e2e phase.
# No network, sudo, apt or Multipass: the helper is sourced in a subshell and
# only its record files are inspected.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OBSERVABILITY_SRC="$ROOT/setup/helpers/observability.sh"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/records"

expect_line() {
	local file=$1 pattern=$2 label=$3
	if grep -qF "$pattern" "$file"; then
		pass "$label"
	else
		fail "$label (missing: $pattern)"
	fi
}

# 1. Enabled: one phase span per phase, with the right name, status and run id.
run_phase() {
	local phase=$1 label=$2 status=$3
	mkdir -p "$T/records/$phase"
	ROOT="$ROOT" OBSERVABILITY_SRC="$OBSERVABILITY_SRC" \
	PHASE="$phase" PHASE_LABEL="$label" PHASE_STATUS="$status" \
	OBSERVABILITY_RECORD_DIR="$T/records/$phase" \
	OBSERVABILITY_E2E_HELPER="$OBSERVABILITY_SRC" \
	OBSERVABILITY_E2E_REAL_CURL=/bin/true \
	OBSERVABILITY_E2E_REAL_WGET=/bin/true \
	OBSERVABILITY_E2E_REAL_GIT=/bin/true \
	OBSERVABILITY_E2E_REAL_SUDO=/bin/true \
	bash -c '
		source "$OBSERVABILITY_SRC"
		source "$ROOT/setup/helpers/steps.sh"
		export OBSERVABILITY_PHASE=$PHASE
		observability_init phase-test ""
		observability_phase_begin "$PHASE_LABEL"
		fake_step() { :; }
		step fake_step
		observability_phase_end "$PHASE_STATUS"
	' || return 1
}

if run_phase install install.sh 0; then
	spans="$T/records/install/spans.jsonl"
	[[ -f $spans ]] && pass "install: spans recorded" || fail "install: no spans"
	if [[ -f $spans ]]; then
		count=$(grep -c '"kind":"phase"' "$spans")
		[[ $count -eq 1 ]] && pass "install: exactly one phase span" || fail "install: $count phase spans"
		expect_line "$spans" '"kind":"phase"' "install: kind is phase"
		expect_line "$spans" '"name":"install.sh"' "install: name matches"
		expect_line "$spans" '"phase":"install"' "install: phase matches"
		expect_line "$spans" '"status":"ok"' "install: ok status"
		expect_line "$spans" '"exit_code":0' "install: exit code"
		expect_line "$spans" '"kind":"step"' "install: step span still recorded"
	fi
else
	fail "install: phase run failed"
fi

if run_phase post-install post-install.sh 1; then
	spans="$T/records/post-install/spans.jsonl"
	if [[ -f $spans ]]; then
		expect_line "$spans" '"name":"post-install.sh"' "post-install: name matches"
		expect_line "$spans" '"phase":"post-install"' "post-install: phase matches"
		expect_line "$spans" '"status":"error"' "post-install: error status"
		expect_line "$spans" '"exit_code":1' "post-install: exit code"
	else
		fail "post-install: no spans"
	fi
else
	fail "post-install: phase run failed"
fi

# 2. Disabled: no span file at all when observability was never initialized.
mkdir -p "$T/disabled"
if OBSERVABILITY_SRC="$OBSERVABILITY_SRC" OBSERVABILITY_RECORD_DIR="$T/disabled" \
	OBSERVABILITY_E2E_HELPER="$OBSERVABILITY_SRC" bash -c '
		source "$OBSERVABILITY_SRC"
		observability_phase_begin install.sh
		observability_phase_end 0
	'; then
	[[ ! -e $T/disabled/spans.jsonl ]] &&
		pass "disabled: no spans emitted" || fail "disabled: spans emitted"
else
	fail "disabled: helpers failed when observability off"
fi

# 3. The per-step summary filter still excludes anything that is not a step.
if grep -qF '"kind":"step"' "$ROOT/tests/e2e-observability.sh"; then
	pass "summary: filters on step spans"
else
	fail "summary: step filter missing"
fi

[[ $FAILURES -eq 0 ]] || exit 1
