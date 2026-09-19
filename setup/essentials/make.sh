#!/usr/bin/env bash

install_make() {
	local installed_ver
	if installed_ver="$(make_version 2>/dev/null)"; then
		printf 'skip: make already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo apt install -y make
}

make_version() {
	make --version 2>/dev/null | head -n 1 | grep .
}
