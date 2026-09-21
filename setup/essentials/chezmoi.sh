#!/usr/bin/env bash

install_chezmoi() {
	local installed_ver
	if installed_ver="$(chezmoi_version 2>/dev/null)"; then
		printf 'skip: chezmoi already installed (%s)\n' "$installed_ver"
		return 0
	fi
	local tmpdir
	tmpdir="$(mktemp -d)"
	sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$tmpdir"
	sudo mv "$tmpdir/chezmoi" /usr/local/bin/chezmoi
	rm -rf "$tmpdir"
}

chezmoi_version() {
	chezmoi --version 2>/dev/null | head -n 1 | grep .
}
