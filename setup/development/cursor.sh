#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_cursor_cli() {
	local installed_ver
	if installed_ver="$(cursor_cli_version 2>/dev/null)"; then
		printf 'skip: cursor-cli already installed (%s)\n' "$installed_ver"
		return 0
	fi
	curl https://cursor.com/install -fsS | bash
}

install_cursor() {
	local installed_ver
	if installed_ver="$(cursor_version 2>/dev/null)"; then
		printf 'skip: cursor already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo apt install -y cursor
}

# The cursor .deb postinst registers this source with its own key; match it so reruns see one Signed-By.
install_cursor_repository() {
	curl -fsSL https://downloads.cursor.com/keys/anysphere.asc | gpg --dearmor | sudo tee /usr/share/keyrings/anysphere.gpg >/dev/null
	sudo tee /etc/apt/sources.list.d/cursor.sources >/dev/null <<'EOF'
Types: deb
URIs: https://downloads.cursor.com/aptrepo
Suites: stable
Components: main
Architectures: amd64,arm64
Signed-By: /usr/share/keyrings/anysphere.gpg
EOF
	sudo rm -f /etc/apt/sources.list.d/cursor.list /etc/apt/keyrings/cursor.gpg
}

cursor_cli_version() {
	if command -v cursor >/dev/null 2>&1; then
		cursor --version 2>/dev/null | head -n 1 | grep .
	elif command -v cursor-agent >/dev/null 2>&1; then
		cursor-agent --version 2>/dev/null | head -n 1 | grep .
	else
		return 1
	fi
}

cursor_version() {
	dpkg -s cursor 2>/dev/null | grep "^Version:"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
