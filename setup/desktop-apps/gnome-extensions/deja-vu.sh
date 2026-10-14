#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../../helpers/dispatcher.sh"

# Pinned EGO release: v17 (version_tag 76198) covers Shell 46-51.
# UUID keeps the upstream name; repo-side identifiers use deja-vu.
DEJA_VU_UUID="deja-window@mcast.gnomext.com"
DEJA_VU_VERSION="17"
DEJA_VU_URL="https://extensions.gnome.org/download-extension/${DEJA_VU_UUID}.shell-extension.zip?version_tag=76198"

deja_vu_download() {
	curl -fsSL "$DEJA_VU_URL" -o "$1"
}

deja_vu_extract() {
	unzip -oq "$1" -d "$2"
}

deja_vu_publish() {
	mkdir -p "$(dirname "$2")" || return 1
	rm -rf "$2" && mv "$1" "$2"
}

deja_vu_compile_schemas() {
	if command -v glib-compile-schemas >/dev/null 2>&1; then
		glib-compile-schemas "$1/schemas" 2>/dev/null || true
	fi
}

install_deja_vu() {
	local installed_ver
	if installed_ver="$(deja_vu_version 2>/dev/null)" && [[ $installed_ver == "$DEJA_VU_VERSION" ]]; then
		printf 'skip: deja-vu already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo apt-get install -y unzip || return 1
	local work zip stage dir
	work="$(mktemp -d)" || return 1
	trap 'rm -rf "$work"' RETURN
	zip="$work/deja-vu.zip"
	stage="$work/stage"
	mkdir -p "$stage" || return 1
	deja_vu_download "$zip" || return 1
	deja_vu_extract "$zip" "$stage" || return 1
	dir="$HOME/.local/share/gnome-shell/extensions/$DEJA_VU_UUID"
	deja_vu_publish "$stage" "$dir" || return 1
	deja_vu_compile_schemas "$dir"
}

config_deja_vu() {
	# Cheap state: enable on every run. No-op without gnome-extensions
	# (server VMs); the next graphical login picks it up. Failures
	# propagate when the tool exists so a disabled extension is visible.
	command -v gnome-extensions >/dev/null 2>&1 || return 0
	gnome-extensions enable "$DEJA_VU_UUID"
}

deja_vu_version() {
	grep -o '"version": [0-9]*' "$HOME/.local/share/gnome-shell/extensions/$DEJA_VU_UUID/metadata.json" 2>/dev/null | head -n 1 | grep -o '[0-9]*'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
