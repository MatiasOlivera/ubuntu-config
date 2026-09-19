#!/usr/bin/env bash

install_curl() {
	local installed_ver
	if installed_ver="$(curl_version 2>/dev/null)"; then
		printf 'skip: curl already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo apt install -y curl
}

curl_version() {
	curl --version 2>/dev/null | head -n 1 | grep .
}
