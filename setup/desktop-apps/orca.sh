#!/usr/bin/env bash

install_orca() {
	local installed_ver
	if installed_ver="$(orca_version 2>/dev/null)"; then
		printf 'skip: orca already installed (%s)\n' "$installed_ver"
		return 0
	fi
	local ver="1.4.206"
	curl -fsSLO "https://github.com/stablyai/orca/releases/download/v${ver}/orca-ide_${ver}_amd64.deb"
	sudo apt install -y "./orca-ide_${ver}_amd64.deb" || return 1
	rm -f "orca-ide_${ver}_amd64.deb"
}

orca_version() {
	dpkg -s orca-ide 2>/dev/null | grep "^Version:"
}