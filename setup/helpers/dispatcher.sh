#!/usr/bin/env bash

dispatch_command() {
	local component=main command
	case $# in
		0)
			printf 'usage: %s [component] {install|repository|config|version}\n' "$0"
			return 0
			;;
		1) command=$1 ;;
		2) component=$1 command=$2 ;;
		*)
			printf 'usage: %s [component] {install|repository|config|version}\n' "$0" >&2
			return 2
			;;
	esac

	local package=${DISPATCH_PACKAGE:-$(basename "$0" .sh | tr '-' '_')}
	local target
	if [[ $component == main ]]; then
		case $command in
			install) target="install_${package}" ;;
			repository) target="install_${package}_repository" ;;
			config) target="config_${package}" ;;
			version) target="${package}_version" ;;
			*) printf 'error: unknown command: %s\n' "$command" >&2; return 2 ;;
		esac
		if ! declare -F "$target" >/dev/null; then
			case $command in
				install) mapfile -t targets < <(declare -F | awk '{print $3}' | grep '^install_' | grep -v '_repository$') ;;
				repository) mapfile -t targets < <(declare -F | awk '{print $3}' | grep '^install_.*_repository$') ;;
				config) mapfile -t targets < <(declare -F | awk '{print $3}' | grep '^config_') ;;
				version) mapfile -t targets < <(declare -F | awk '{print $3}' | grep '_version$') ;;
			esac
			if [[ ${#targets[@]} -eq 1 ]]; then
				target=${targets[0]}
			fi
		fi
	else
		case $command in
			install) target="install_${package}_${component}" ;;
			repository) target="install_${package}_${component}_repository" ;;
			config) target="config_${package}_${component}" ;;
			version) target="${package}_${component}_version" ;;
			*) printf 'error: unknown command: %s\n' "$command" >&2; return 2 ;;
		esac
	fi

	if ! declare -F "$target" >/dev/null; then
		printf 'error: unknown %s or command: %s %s\n' \
			"$([[ $component == main ]] && printf 'package' || printf 'component')" \
			"$component" "$command" >&2
		return 2
	fi
	"$target"
}
