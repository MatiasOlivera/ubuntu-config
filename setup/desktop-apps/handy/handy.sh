#!/usr/bin/env bash

install_handy() {
	local installed_ver
	if installed_ver="$(handy_version 2>/dev/null)"; then
		printf 'skip: handy already installed (%s)\n' "$installed_ver"
		return 0
	fi
	local ver="0.9.7"
	curl -fsSLO "https://github.com/cjpais/Handy/releases/download/v${ver}/Handy_${ver}_amd64.deb"
	sudo apt install -y "./Handy_${ver}_amd64.deb"
	rm -f "Handy_${ver}_amd64.deb"
}

handy_version() {
	dpkg -s handy 2>/dev/null | grep "^Version:"
}
