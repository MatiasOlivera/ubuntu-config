#!/usr/bin/env bash

install_chrome() {
	local installed_ver
	if installed_ver="$(chrome_version 2>/dev/null)"; then
		printf 'skip: chrome already installed (%s)\n' "$installed_ver"
		return 0
	fi
	curl -fsSLO https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
	sudo apt install -y ./google-chrome-stable_current_amd64.deb
	rm -f google-chrome-stable_current_amd64.deb
}

chrome_version() {
	if command -v google-chrome >/dev/null 2>&1; then
		google-chrome --version 2>/dev/null | head -n 1 | grep .
	elif command -v google-chrome-stable >/dev/null 2>&1; then
		google-chrome-stable --version 2>/dev/null | head -n 1 | grep .
	else
		return 1
	fi
}
