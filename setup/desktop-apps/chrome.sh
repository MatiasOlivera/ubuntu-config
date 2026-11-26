#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/apt-source.sh"

install_chrome() {
	local installed_ver
	if installed_ver="$(chrome_version 2>/dev/null)"; then
		printf 'skip: chrome already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo apt install -y google-chrome-stable
}

# Match the source and key the vendor .deb postinst writes so both owners converge.
install_chrome_repository() {
	curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor --yes -o /usr/share/keyrings/google-chrome.gpg
	apt_source_write google-chrome.sources <<'EOF'
Types: deb
URIs: https://dl.google.com/linux/chrome-stable/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/google-chrome.gpg
EOF
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

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
