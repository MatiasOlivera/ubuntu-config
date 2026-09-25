#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_github_cli_repository() {
	sudo install -m 0755 -d /etc/apt/keyrings
	sudo curl -fsSL \
		https://cli.github.com/packages/githubcli-archive-keyring.gpg \
		-o /etc/apt/keyrings/githubcli-archive-keyring.gpg
	sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
	sudo tee /etc/apt/sources.list.d/github-cli.sources >/dev/null <<EOF
Types: deb
URIs: https://cli.github.com/packages
Suites: stable
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/githubcli-archive-keyring.gpg
EOF
}

install_github_cli() {
	local installed_ver
	if installed_ver="$(github_cli_version 2>/dev/null)"; then
		printf 'skip: GitHub CLI already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo apt install -y gh
}

github_cli_version() {
	gh --version 2>/dev/null | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
