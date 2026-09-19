#!/usr/bin/env bash

install_flatpak() {
	local installed_ver
	if installed_ver="$(flatpak_version 2>/dev/null)"; then
		printf 'skip: flatpak already installed (%s)\n' "$installed_ver"
	else
		sudo apt install -y flatpak gnome-software-plugin-flatpak
	fi
	flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

flatpak_version() {
	flatpak --version 2>/dev/null | head -n 1 | grep .
}
