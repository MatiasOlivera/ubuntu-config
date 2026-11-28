#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_obsidian() {
	local installed_ver
	if installed_ver="$(obsidian_version 2>/dev/null)"; then
		printf 'skip: obsidian already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo flatpak install flathub -y md.obsidian.Obsidian
}

obsidian_version() {
	flatpak info md.obsidian.Obsidian 2>/dev/null | grep -i "Version:" | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
