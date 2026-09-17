#!/usr/bin/env bash

install_chezmoi() {
	command -v chezmoi >/dev/null 2>&1 && return 0
	local tmpdir
	tmpdir="$(mktemp -d)"
	sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$tmpdir"
	sudo mv "$tmpdir/chezmoi" /usr/local/bin/chezmoi
	rm -rf "$tmpdir"
}
