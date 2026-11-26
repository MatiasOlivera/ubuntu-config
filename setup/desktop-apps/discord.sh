#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_discord() {
	local installed_ver
	if installed_ver="$(discord_version 2>/dev/null)"; then
		printf 'skip: discord already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo flatpak install flathub -y com.discordapp.Discord
}

discord_version() {
	flatpak info com.discordapp.Discord 2>/dev/null | grep -i "Version:" | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
