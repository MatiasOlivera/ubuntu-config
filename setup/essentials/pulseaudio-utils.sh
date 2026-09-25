#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_pulseaudio_utils() {
	local installed_ver
	if installed_ver="$(pulseaudio_utils_version 2>/dev/null)"; then
		printf 'skip: pulseaudio-utils already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo apt install -y pulseaudio-utils
}

pulseaudio_utils_version() {
	pactl --version 2>/dev/null | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
