#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_keyring() {
	local installed_ver
	if installed_ver="$(keyring_version 2>/dev/null)"; then
		printf 'skip: libsecret-tools already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo apt install -y libsecret-tools
}

keyring_version() {
	dpkg-query -W -f='${Version}' libsecret-tools 2>/dev/null | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
