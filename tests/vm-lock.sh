#!/usr/bin/env bash
#
# vm-lock.sh — one active e2e run per VM. Source and call vm_lock_acquire.
# Ownership is held by the process and released by the kernel on exit.

vm_lock_fd=

vm_lock_path() {
	printf '%s/ubuntu-workstation-e2e-%s.lock' "${TMPDIR:-/tmp}" "$1"
}

vm_lock_release() {
	if [[ -n $vm_lock_fd ]]; then
		exec {vm_lock_fd}>&-
		vm_lock_fd=
	fi
}

vm_lock_acquire() {
	local vm="${1:-}" path
	if [[ -z $vm ]]; then
		printf 'e2e VM lock: no VM name given\n' >&2
		return 1
	fi
	if ! command -v flock >/dev/null 2>&1; then
		printf 'e2e VM %s: flock is required to guard concurrent runs\n' "$vm" >&2
		return 1
	fi

	path="$(vm_lock_path "$vm")"
	# Pre-create so a redirection failure cannot exit the sourcing shell.
	if ! : > "$path"; then
		printf 'e2e VM %s: cannot create lock file %s\n' "$vm" "$path" >&2
		return 1
	fi
	exec {vm_lock_fd}>"$path"
	if ! flock -n "$vm_lock_fd"; then
		vm_lock_release
		printf 'another e2e run is already using VM %s; aborting\n' "$vm" >&2
		return 1
	fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	[[ $# -eq 1 ]] || {
		printf 'Usage: %s <vm-name>\n' "$0" >&2
		exit 1
	}
	vm_lock_acquire "$1" || exit 1
	printf 'holding VM %s (interrupt to release)\n' "$1"
	while :; do
		sleep 60
	done
fi
