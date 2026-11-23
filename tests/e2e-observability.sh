#!/usr/bin/env bash
#
# e2e-observability.sh — run one e2e phase with durable records and a live
# transcript. Replaces the single whole-run log helper. Records are copied out
# of the VM after the command finishes, including on failure.

set -o pipefail

usage() {
	printf 'Usage: %s <phase> <cmd> [args...]\n' "$0" >&2
	exit 2
}

[[ $# -ge 2 ]] || usage
phase=$1
shift

root=${E2E_OBSERVABILITY_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ubuntu-config/observability}
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
run_dir="$root/$run_id"
mkdir -p "$run_dir" || exit 1
log="$run_dir/$phase-console.log"
printf 'records: %s\nlog: %s\n' "$run_dir" "$log"

# One bounded probe: an unreachable collector only disables live forwarding.
if [[ -n ${OBS_COLLECTOR:-} ]]; then
	if ! curl -sS --max-time 2 -o /dev/null "$OBS_COLLECTOR/health" 2>/dev/null; then
		printf 'warning: live observability collector unreachable; continuing with durable records only\n' >&2
		OBS_COLLECTOR=
	fi
fi
export OBS_COLLECTOR

"$@" 2>&1 | tee "$log"
rc=$?

copy_records() {
	local archive="/tmp/ubuntu-config-observability-$$.tgz"
	[[ -n ${OBS_VM_NAME:-} && -n ${OBS_VM_RECORD_DIR:-} ]] || return 0
	if multipass exec "$OBS_VM_NAME" -- tar -czf "$archive" -C "$OBS_VM_RECORD_DIR" . >/dev/null 2>&1 &&
		multipass transfer "$OBS_VM_NAME:$archive" "$run_dir/records.tgz" >/dev/null 2>&1; then
		tar -xzf "$run_dir/records.tgz" -C "$run_dir" 2>/dev/null || true
		rm -f "$run_dir/records.tgz"
	else
		printf 'warning: could not copy e2e records from the VM\n' >&2
	fi
}

write_summary() {
	local spans="$run_dir/spans.jsonl" out="$run_dir/summary.tsv" line name status duration
	printf 'label\tphase\tstatus\tduration_ms\n' > "$out"
	[[ -f $spans ]] || return 0
	while IFS= read -r line; do
		[[ $line == *'"kind":"step"'* ]] || continue
		name=$(printf '%s\n' "$line" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')
		status=$(printf '%s\n' "$line" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
		duration=$(printf '%s\n' "$line" | sed -n 's/.*"duration_ms":\([0-9]*\).*/\1/p')
		printf '%s\t%s\t%s\t%s\n' "$name" "$phase" "$status" "$duration" >> "$out"
	done < "$spans"
}

copy_records
write_summary

printf 'exit: %d\n' "$rc"
printf '%s\n' '--- tail ---'
tail -n 20 "$log"
exit "$rc"
