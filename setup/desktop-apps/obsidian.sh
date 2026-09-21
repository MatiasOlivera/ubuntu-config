#!/usr/bin/env bash

install_obsidian() {
	local installed_ver
	if installed_ver="$(obsidian_version 2>/dev/null)"; then
		printf 'skip: obsidian already installed (%s)\n' "$installed_ver"
		return 0
	fi
	local ver="1.13.7"
	curl -fsSLO "https://github.com/obsidianmd/obsidian-releases/releases/download/v${ver}/obsidian_${ver}_amd64.deb"
	sudo apt install -y "./obsidian_${ver}_amd64.deb"
	rm -f "obsidian_${ver}_amd64.deb"
}

obsidian_version() {
	dpkg -s obsidian 2>/dev/null | grep "^Version:"
}
