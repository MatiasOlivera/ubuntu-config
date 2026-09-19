#!/usr/bin/env bash

install_git() {
	local installed_ver
	if installed_ver="$(git_version 2>/dev/null)"; then
		printf 'skip: git already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo apt-get install -y git
}

git_version() {
	git --version 2>/dev/null | head -n 1 | grep .
}
