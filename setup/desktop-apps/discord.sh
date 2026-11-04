#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_discord() {
	local installed_ver
	if installed_ver="$(discord_version 2>/dev/null)"; then
		printf 'skip: discord already installed (%s)\n' "$installed_ver"
		return 0
	fi
	curl -fsSL -o discord.deb "https://discord.com/api/download?platform=linux&format=deb"
	sudo apt install -y ./discord.deb
	rm -f discord.deb
}

discord_version() {
	dpkg -s discord 2>/dev/null | grep "^Version:"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
