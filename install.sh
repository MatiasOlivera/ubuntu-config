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

SCRIPT_DIR=$(dirname "$0")

ESSENTIALS_DIR="$SCRIPT_DIR/essentials"
DESKTOP_APPS_DIR="$SCRIPT_DIR/desktop-apps"
DEVELOPMENT_DIR="$SCRIPT_DIR/development"

source "$ESSENTIALS_DIR/make.sh"
source "$ESSENTIALS_DIR/curl.sh"
source "$ESSENTIALS_DIR/flatpak.sh"
source "$ESSENTIALS_DIR/pulseaudio-utils.sh"
source "$ESSENTIALS_DIR/fuse.sh"

source "$DESKTOP_APPS_DIR/timeshift.sh"
source "$DESKTOP_APPS_DIR/fsearch.sh"
source "$DESKTOP_APPS_DIR/chrome.sh"
source "$DESKTOP_APPS_DIR/obs.sh"
source "$DESKTOP_APPS_DIR/spotify.sh"

source "$DEVELOPMENT_DIR/git/git.sh"
source "$DEVELOPMENT_DIR/git/git-config.sh"
source "$DEVELOPMENT_DIR/cursor.sh"
source "$DEVELOPMENT_DIR/docker.sh"
source "$DEVELOPMENT_DIR/postman.sh"
source "$DEVELOPMENT_DIR/beekeeper-studio.sh"
source "$DEVELOPMENT_DIR/zsh/zsh.sh"
source "$DEVELOPMENT_DIR/zsh/zsh-config.sh"
source "$DEVELOPMENT_DIR/zoxide.sh"

# Essentials
install_make
install_curl
install_flatpak
install_pulseaudio_utils
install_fuse

# Desktop Apps
install_timeshift
install_fsearch
install_chrome
install_obs
install_spotify

# Development
install_git
configure_git "$name" "$email"
install_cursor_cli
install_docker
install_postman
install_beekeeper_studio
install_zsh
configure_zsh
install_zoxide