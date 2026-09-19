#!/usr/bin/env bash

install_vscode() {
	local installed_ver
	if installed_ver="$(vscode_version 2>/dev/null)"; then
		printf 'skip: vscode already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo apt install -y code
}

install_vscode_repository() {
	curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
	sudo tee /etc/apt/sources.list.d/vscode.sources >/dev/null <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
}

vscode_version() {
	code --version 2>/dev/null | head -n 1 | grep .
}
