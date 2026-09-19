#!/usr/bin/env bash

install_fonts() {
	sudo apt install -y unzip fontconfig fonts-firacode

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
