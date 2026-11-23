#!/usr/bin/env bash
# Shared step runner for setup/install.sh and setup/post-install.sh.
# Times each step, remembers failed ones, and reports them at the end of the
# run. FAIL_FAST=1 exits on the first failed step instead of collecting them.

FAILED_STEPS=()

step() {
	local label=$1
	local t0=$SECONDS
	[[ $# -gt 1 ]] && shift
	declare -F observability_step_begin >/dev/null 2>&1 && observability_step_begin "$label"
	local st
	if declare -F observability_step_begin >/dev/null 2>&1 && [[ ${OBSERVABILITY_INITIALIZED:-0} == 1 ]]; then
		"$@" 2>&1 | tee "$OBSERVABILITY_CURRENT_LOG"
		st=${PIPESTATUS[0]}
	else
		"$@"
		st=$?
	fi
	printf '[+%ds] %s\n' "$((SECONDS - t0))" "$label"
	if [[ $st -ne 0 ]]; then
		printf 'FAILED: %s (status %d)\n' "$label" "$st" >&2
		FAILED_STEPS+=("$label")
		if [[ ${FAIL_FAST:-0} == 1 ]]; then
			exit "$st"
		fi
	fi
	declare -F observability_step_end >/dev/null 2>&1 && observability_step_end "$st"
	return "$st"
}

# Advisory steps (credential sync) are timed but never counted or fail the run.
advisory_step() {
	local label=$1
	local t0=$SECONDS
	[[ $# -gt 1 ]] && shift
	declare -F observability_step_begin >/dev/null 2>&1 && observability_step_begin "$label"
	local st
	if declare -F observability_step_begin >/dev/null 2>&1 && [[ ${OBSERVABILITY_INITIALIZED:-0} == 1 ]]; then
		"$@" 2>&1 | tee "$OBSERVABILITY_CURRENT_LOG"
		st=${PIPESTATUS[0]}
	else
		"$@"
		st=$?
	fi
	printf '[+%ds] %s\n' "$((SECONDS - t0))" "$label"
	declare -F observability_step_end >/dev/null 2>&1 && observability_step_end "$st"
	return 0
}

report_failed_steps() {
	if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
		printf '%d step(s) failed: %s\n' "${#FAILED_STEPS[@]}" "${FAILED_STEPS[*]}" >&2
		return 1
	fi
	return 0
}
