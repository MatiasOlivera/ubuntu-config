#!/usr/bin/env bash
#
# vm-name.sh — print the worktree-scoped Multipass VM name for a checkout.
# One checkout = one stable VM, so concurrent agents never share a machine.
# Usage: vm-name.sh [worktree-path]   (default: current directory)

# Convert a non-negative integer to base62 (0-9a-zA-Z).
base62() {
	local n="$1" out=''
	local digits='0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
	while (( n > 0 )); do
		out="${digits:n % 62:1}$out"
		n=$((n / 62))
	done
	printf '%s' "${out:-0}"
}

# Sourced for unit tests: define base62 without running the CLI.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	worktree="${1:-$PWD}"

	# Readable, Multipass-safe slug from the checkout directory name.
	slug="$(basename "$worktree" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-')"
	slug="${slug:0:24}"
	slug="${slug#-}"
	slug="${slug%%-}"
	[[ -n $slug ]] || slug="repo"

	# 48-bit digest of the full path, encoded in base62 (alphanumeric, <=9 chars).
	hex="$(printf '%s\n' "$worktree" | sha256sum)"
	suffix="$(base62 "$((16#${hex:0:12}))")"

	printf 'ubuntu-workstation-test-%s-%s\n' "$slug" "$suffix"
fi
