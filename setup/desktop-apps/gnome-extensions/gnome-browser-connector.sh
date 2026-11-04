#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../../helpers/dispatcher.sh"

install_gnome_browser_connector() {
	local installed_ver
	if installed_ver="$(gnome_browser_connector_version 2>/dev/null)"; then
		printf 'skip: gnome-browser-connector already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo apt-get install -y gnome-browser-connector
}

gnome_browser_connector_version() {
	dpkg -s gnome-browser-connector 2>/dev/null | grep "^Version:"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
