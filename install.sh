#!/usr/bin/env bash

usage() {
	printf 'Usage: %s --name "Your Name" --email "you@example.com"\n' "$0" >&2
}

name=
email=

while [[ $# -gt 0 ]]; do
	case $1 in
		--name)
			if [[ $# -lt 2 ]]; then
				usage
				exit 1
			fi
			name=$2
			shift 2
			;;
		--email)
			if [[ $# -lt 2 ]]; then
				usage
				exit 1
			fi
			email=$2
			shift 2
			;;
		*)
			usage
			exit 1
			;;
	esac
done

if [[ -z $name || -z $email ]]; then
	usage
	exit 1
fi

source "$(dirname "$0")/git-config.sh"

## Essentials ##

# Make
sudo apt install make

# curl
sudo apt install curl

# Timeshift
sudo apt-get install timeshift

# Flatpak (for OBS)
# https://flathub.org/en/setup/Ubuntu
sudo apt install flatpak
sudo apt install gnome-software-plugin-flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# FSearch
sudo add-apt-repository ppa:christian-boxdoerfer/fsearch-daily
sudo apt update
sudo apt install fsearch

## Apps ##

# Chrome
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo dpkg -i google-chrome-stable_current_amd64.deb

# OBS Studio
# https://flathub.org/en/apps/com.obsproject.Studio
flatpak install flathub com.obsproject.Studio

# OBS Plugins
sudo apt-get install obs-advanced-masks

# Spotify
# https://www.spotify.com/es/download/linux/

curl -sS https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
echo "deb https://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list

sudo apt-get update && sudo apt-get install spotify-client

## Development ##

# Git
sudo apt-get install git

configure_git "$name" "$email"