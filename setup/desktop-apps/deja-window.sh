#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

# Pinned EGO release: v17 (version_tag 76198) covers Shell 46-51.
DEJA_WINDOW_UUID="deja-window@mcast.gnomext.com"
DEJA_WINDOW_VERSION="17"
DEJA_WINDOW_URL="https://extensions.gnome.org/download-extension/${DEJA_WINDOW_UUID}.shell-extension.zip?version_tag=76198"

deja_window_dependencies() {
	sudo apt-get install -y gnome-browser-connector unzip
}

install_deja_window() {
	local installed_ver
	if installed_ver="$(deja_window_version 2>/dev/null)" && [[ $installed_ver == "$DEJA_WINDOW_VERSION" ]]; then
		printf 'skip: deja-window already installed (%s)\n' "$installed_ver"
		return 0
	fi
	deja_window_dependencies
	local tmp dir
	tmp="$(mktemp -d)"
	curl -fsSL "$DEJA_WINDOW_URL" -o "$tmp/deja-window.zip"
	dir="$HOME/.local/share/gnome-shell/extensions/$DEJA_WINDOW_UUID"
	mkdir -p "$dir"
	unzip -oq "$tmp/deja-window.zip" -d "$dir"
	rm -rf "$tmp"
	if command -v glib-compile-schemas >/dev/null 2>&1; then
		glib-compile-schemas "$dir/schemas" 2>/dev/null || true
	fi
}

config_deja_window() {
	# Cheap state: enable on every run. No-op without a GNOME session
	# (server VMs); the next graphical login picks it up.
	command -v gnome-extensions >/dev/null 2>&1 || return 0
	gnome-extensions enable "$DEJA_WINDOW_UUID" 2>/dev/null || true
}

gnome_browser_connector_version() {
	dpkg -s gnome-browser-connector 2>/dev/null | grep "^Version:"
}

deja_window_version() {
	grep -o '"version": [0-9]*' "$HOME/.local/share/gnome-shell/extensions/$DEJA_WINDOW_UUID/metadata.json" 2>/dev/null | head -n 1 | grep -o '[0-9]*'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
