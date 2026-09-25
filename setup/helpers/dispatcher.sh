#!/usr/bin/env bash

dispatch_command() {
	local command=${1:-help}
	shift || true

	if [[ $command == help ]]; then
		printf 'usage: %s\n' "$1"
		return 0
	fi

	local mapping target
	for mapping in "$@"; do
		if [[ $mapping == "$command="* ]]; then
			target=${mapping#*=}
			if ! declare -F "$target" >/dev/null; then
				printf 'error: undefined command function: %s\n' "$target" >&2
				return 127
			fi
			"$target"
			return
		fi
	done

	printf 'error: unknown command: %s\n' "$command" >&2
	return 2
}
