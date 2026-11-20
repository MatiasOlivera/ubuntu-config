#!/usr/bin/env bash
#
# run-with-logging.sh — run a long command with a live, timestamped log.
# Prints the log path up front (so it can be tailed mid-run), streams
# stdout+stderr to it, then reports the exit status and a tail. Fail-closed:
# returns a failure if the command fails or the log cannot be written.

set -o pipefail

usage() {
	printf 'Usage: %s <name> <cmd> [args...]\n' "$0" >&2
	exit 2
}

[[ $# -ge 2 ]] || usage
name=$1
shift

log="${TMPDIR:-/tmp}/ubuntu-config-$name-$(date +%Y%m%d-%H%M%S)-$$.log"
printf 'log: %s\n' "$log"

"$@" 2>&1 | tee "$log"
rc=$?

# tee has exited, so this summary is console-only and is not fed back into the log.
printf 'exit: %d\nlog: %s\n--- tail ---\n' "$rc" "$log"
tail -n 20 "$log"
exit "$rc"
