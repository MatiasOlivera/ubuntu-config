#!/usr/bin/env bash

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

install_cursor_repository() {
	curl -fsSL https://downloads.cursor.com/keys/anysphere.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/cursor.gpg >/dev/null
	echo "deb [arch=amd64,arm64 signed-by=/etc/apt/keyrings/cursor.gpg] https://downloads.cursor.com/aptrepo stable main" | sudo tee /etc/apt/sources.list.d/cursor.list
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
