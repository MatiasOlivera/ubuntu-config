#!/usr/bin/env bash

install_gitkraken() {
	local installed_ver
	if installed_ver="$(gitkraken_version 2>/dev/null)"; then
		printf 'skip: gitkraken already installed (%s)\n' "$installed_ver"
		return 0
	fi
	curl -fsSLO https://release.gitkraken.com/linux/gitkraken-amd64.deb
	sudo apt install -y ./gitkraken-amd64.deb
	rm -f gitkraken-amd64.deb
}

gitkraken_version() {
	dpkg -s gitkraken 2>/dev/null | grep "^Version:"
}
