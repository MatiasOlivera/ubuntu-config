#!/usr/bin/env bash

install_obsidian() {
	local ver="1.13.7"
	curl -fsSLO "https://github.com/obsidianmd/obsidian-releases/releases/download/v${ver}/obsidian_${ver}_amd64.deb"
	sudo apt install -y "./obsidian_${ver}_amd64.deb"
	rm -f "obsidian_${ver}_amd64.deb"
}
