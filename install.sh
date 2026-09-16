#!/usr/bin/env bash

usage() {
	printf 'Usage: %s --name "Your Name" --email "you@example.com"\n' "$0" >&2
}

name=
email=

while [[ $# -gt 0 ]]; do
	case $1 in
	--name) name=$2 ;;
	--email) email=$2 ;;
	*) usage; exit 1 ;;
	esac
	[[ $# -lt 2 ]] && { usage; exit 1; }
	shift 2
done

[[ -z $name || -z $email ]] && { usage; exit 1; }

SCRIPT_DIR=$(dirname "$0")

ESSENTIALS_DIR="$SCRIPT_DIR/essentials"
DESKTOP_APPS_DIR="$SCRIPT_DIR/desktop-apps"
DEVELOPMENT_DIR="$SCRIPT_DIR/development"

source "$ESSENTIALS_DIR/make.sh"
source "$ESSENTIALS_DIR/curl.sh"
source "$ESSENTIALS_DIR/flatpak.sh"
source "$ESSENTIALS_DIR/pulseaudio-utils.sh"
source "$ESSENTIALS_DIR/fuse.sh"
source "$ESSENTIALS_DIR/synaptic.sh"
source "$ESSENTIALS_DIR/python3/python3-pip.sh"
source "$ESSENTIALS_DIR/python3/python3-pipx.sh"

source "$DESKTOP_APPS_DIR/timeshift.sh"
source "$DESKTOP_APPS_DIR/fsearch.sh"
source "$DESKTOP_APPS_DIR/chrome.sh"
source "$DESKTOP_APPS_DIR/obs/obs.sh"
source "$DESKTOP_APPS_DIR/obs/obs-plugins.sh"
source "$DESKTOP_APPS_DIR/spotify.sh"
source "$DESKTOP_APPS_DIR/handy/handy-config.sh"

source "$DEVELOPMENT_DIR/git/git.sh"
source "$DEVELOPMENT_DIR/git/git-config.sh"
source "$DEVELOPMENT_DIR/cursor.sh"
source "$DEVELOPMENT_DIR/docker.sh"
source "$DEVELOPMENT_DIR/postman.sh"
source "$DEVELOPMENT_DIR/beekeeper-studio.sh"
source "$DEVELOPMENT_DIR/zsh/zsh.sh"
source "$DEVELOPMENT_DIR/zsh/zsh-config.sh"
source "$DEVELOPMENT_DIR/zoxide.sh"
source "$DEVELOPMENT_DIR/opencode/opencode.sh"
source "$DEVELOPMENT_DIR/ghostty/ghostty.sh"
source "$DEVELOPMENT_DIR/ghostty/ghostty-config.sh"
source "$DEVELOPMENT_DIR/ollama.sh"

# Essentials
install_make
install_curl
install_flatpak
install_pulseaudio_utils
install_fuse
install_synaptic
install_pip
install_pipx

# Desktop Apps
install_timeshift
install_fsearch
install_chrome
install_obs
install_obs_plugins
install_spotify
config_handy

# Development
install_git
config_git "$name" "$email"
install_cursor_cli
install_docker
install_postman
install_beekeeper_studio
install_zsh
config_zsh
install_zoxide
install_opencode
install_ghostty
config_ghostty
install_ollama

bash "$SCRIPT_DIR/verify.sh" || true