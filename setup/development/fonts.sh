#!/usr/bin/env bash

fonts_dependencies() {
	sudo apt install -y unzip fontconfig
}

install_fonts() {
	local installed_ver
	if installed_ver="$(fonts_version 2>/dev/null)"; then
		printf 'skip: fonts already installed (%s)\n' "$installed_ver"
		return 0
	fi
	fonts_dependencies
	sudo apt install -y fonts-firacode

	local dir="$HOME/.local/share/fonts"
	mkdir -p "$dir/Iosevka" "$dir/MesloLGS_NF"

	local ver="34.8.1"
	for variant in "" "Term"; do
		curl -fsSLO "https://github.com/be5invis/Iosevka/releases/download/v${ver}/PkgTTF-Iosevka${variant}-${ver}.zip"
		unzip -oq "PkgTTF-Iosevka${variant}-${ver}.zip" -d "$dir/Iosevka"
		rm -f "PkgTTF-Iosevka${variant}-${ver}.zip"
	done

	for style in Regular Bold Italic "Bold Italic"; do
		curl -fsSL -o "$dir/MesloLGS_NF/MesloLGS NF ${style}.ttf" "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20${style// /%20}.ttf"
	done

	fc-cache -f
}

fonts_version() {
	fc-list 2>/dev/null | grep -qi "firacode" &&
		fc-list 2>/dev/null | grep -qi "iosevka" &&
		fc-list 2>/dev/null | grep -qi "meslo" &&
		echo present
}
