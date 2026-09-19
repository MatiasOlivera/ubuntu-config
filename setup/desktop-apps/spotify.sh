#!/usr/bin/env bash

install_spotify() {
	local installed_ver
	if installed_ver="$(spotify_version 2>/dev/null)"; then
		printf 'skip: spotify already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo apt-get install -y spotify-client
}

install_spotify_repository() {
	curl -sS https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
	echo "deb https://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
}

spotify_version() {
	dpkg -s spotify-client 2>/dev/null | grep "^Version:"
}
