#!/usr/bin/env bash

install_timeshift() {
	local installed_ver
	if installed_ver="$(timeshift_version 2>/dev/null)"; then
		printf 'skip: timeshift already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo apt-get install -y timeshift
}

timeshift_version() {
	timeshift --version 2>/dev/null | head -n 1 | grep .
}
