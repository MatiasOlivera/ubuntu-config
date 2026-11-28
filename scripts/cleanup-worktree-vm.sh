#!/usr/bin/env bash
#
# cleanup-worktree-vm.sh — Orca archive hook: remove this checkout's e2e VM.
# Best effort by design: a cleanup failure must not block workspace deletion.

set -uo pipefail

report() {
	local message="$1"
	local log="${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/ubuntu-workstation/vm-cleanup-failures.log"

	printf 'WARNING: %s\n' "$message" >&2
	mkdir -p "${log%/*}" 2>/dev/null || true
	printf '%s\n' "$message" >> "$log" 2>/dev/null || true
	# Orca discards a successful hook's output, so make leftovers visible.
	if command -v notify-send >/dev/null 2>&1; then
		notify-send 'ubuntu-workstation: leftover e2e VM' "$message" >/dev/null 2>&1 || true
	fi
}

worktree="${ORCA_WORKTREE_PATH:-$PWD}"
if ! worktree="$(cd "$worktree" 2>/dev/null && pwd)"; then
	worktree="${ORCA_WORKTREE_PATH:-$PWD}"
fi

if [[ ! -f "$worktree/tests/vm-name.sh" ]] ||
	! git -C "$worktree" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	report "cannot identify the e2e VM for '$worktree'; check 'multipass list' for leftovers"
	exit 0
fi

vm="$(bash "$worktree/tests/vm-name.sh" "$worktree")" || {
	report "cannot compute the e2e VM name for '$worktree'"
	exit 0
}
if [[ $vm != ubuntu-workstation-test-* ]]; then
	report "unexpected e2e VM name '$vm' for '$worktree'; refusing to delete"
	exit 0
fi

if ! command -v multipass >/dev/null 2>&1; then
	report "multipass is unavailable; e2e VM $vm needs manual cleanup"
	exit 0
fi

if ! listing="$(multipass list 2>/dev/null)"; then
	report "cannot list Multipass VMs; e2e VM $vm needs manual cleanup"
	exit 0
fi
if ! printf '%s\n' "$listing" | grep -qw -- "$vm"; then
	printf 'archive hook (%s): no e2e VM %s to clean up\n' "$worktree" "$vm"
	exit 0
fi

if multipass delete -p "$vm"; then
	printf 'archive hook (%s): removed e2e VM %s\n' "$worktree" "$vm"
	exit 0
fi

report "leftover e2e VM $vm (workspace $worktree); remove manually: multipass delete -p $vm"
exit 0
