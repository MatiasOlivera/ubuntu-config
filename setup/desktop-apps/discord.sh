#!/usr/bin/env bash

install_discord() {
	curl -fsSL -o discord.deb "https://discord.com/api/download?platform=linux&format=deb"
	sudo apt install -y ./discord.deb
	rm -f discord.deb
}
