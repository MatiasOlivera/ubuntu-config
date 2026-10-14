#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../../helpers/dispatcher.sh"

# Pinned EGO release: v17 (version_tag 76198) covers Shell 46-51.
# UUID keeps the upstream name; repo-side identifiers use deja-vu.
DEJA_VU_UUID="deja-window@mcast.gnomext.com"
DEJA_VU_VERSION="17"
DEJA_VU_URL="https://extensions.gnome.org/download-extension/${DEJA_VU_UUID}.shell-extension.zip?version_tag=76198"

install_deja_vu() {
	local installed_ver
	if installed_ver="$(deja_vu_version 2>/dev/null)" && [[ $installed_ver == "$DEJA_VU_VERSION" ]]; then
		printf 'skip: deja-vu already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo apt-get install -y unzip
	local tmp dir
	tmp="$(mktemp -d)" || return 1
	curl -fsSL "$DEJA_VU_URL" -o "$tmp/deja-vu.zip" || { rm -rf "$tmp"; return 1; }
	dir="$HOME/.local/share/gnome-shell/extensions/$DEJA_VU_UUID"
	mkdir -p "$dir"
	unzip -oq "$tmp/deja-vu.zip" -d "$dir" || { rm -rf "$tmp"; return 1; }
	rm -rf "$tmp"
	if command -v glib-compile-schemas >/dev/null 2>&1; then
		glib-compile-schemas "$dir/schemas" 2>/dev/null || true
	fi
}

config_deja_vu() {
	# Cheap state: enable on every run. No-op without a GNOME session
	# (server VMs); the next graphical login picks it up.
	command -v gnome-extensions >/dev/null 2>&1 || return 0
	gnome-extensions enable "$DEJA_VU_UUID" 2>/dev/null || true
}

deja_vu_version() {
	grep -o '"version": [0-9]*' "$HOME/.local/share/gnome-shell/extensions/$DEJA_VU_UUID/metadata.json" 2>/dev/null | head -n 1 | grep -o '[0-9]*'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
