#!/usr/bin/env bash

dispatch_command() {
	local command=${1:-help}
	shift || :

	if [[ $command == help ]]; then
		printf 'usage: %s {install|repository|config|version|function}\n' "$0"
		return 0
	fi

	local target
	if declare -F "$command" >/dev/null; then
		target=$command
	elif [[ $command == install || $command == repository || $command == config || $command == version ]]; then
		case $command in
			install)
				mapfile -t targets < <(declare -F | awk '{print $3}' | grep '^install_' | grep -v '_repository$')
				;;
			repository)
				mapfile -t targets < <(declare -F | awk '{print $3}' | grep '^install_.*_repository$')
				;;
			config)
				mapfile -t targets < <(declare -F | awk '{print $3}' | grep '^config_')
				;;
			version)
				mapfile -t targets < <(declare -F | awk '{print $3}' | grep '_version$')
				;;
		esac
		if [[ ${#targets[@]} -eq 1 ]]; then
			target=${targets[0]}
		else
			printf 'error: %s is ambiguous; use an exact function name\n' "$command" >&2
			return 2
		fi
	else
		printf 'error: unknown command: %s\n' "$command" >&2
		return 2
	fi

	"$target"
}
