#!/usr/bin/env bash
# [Architecture] Uses Command (partial)
# Download a remote installer before executing it. For the documented integrity
# exceptions only: without this, a failed download feeds empty input to the
# interpreter, which exits 0 and hides the failure from the step runner.

remote_install() {
	local url=$1 interpreter=$2
	shift 2
	local script_tmp
	script_tmp="$(mktemp)" || return $?
	(
		trap 'rm -f "$script_tmp"' EXIT
		curl -fsSL "$url" -o "$script_tmp" || exit $?
		"$interpreter" "$script_tmp" "$@"
	)
}
