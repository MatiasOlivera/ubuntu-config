#!/usr/bin/env bash

SCRIPT_DIR=$(dirname "$0")

ESSENTIALS_DIR="$SCRIPT_DIR/essentials"
DESKTOP_APPS_DIR="$SCRIPT_DIR/desktop-apps"
DEVELOPMENT_DIR="$SCRIPT_DIR/development"
DOTFILES_DIR="$SCRIPT_DIR/../dotfiles"

# ponytail: SECONDS wall-clock per step, no external profiler.
install_start=$SECONDS
step() {
	local label=$1
	local t0=$SECONDS
	if [[ $# -gt 1 ]]; then shift; fi
	"$@"
	local st=$?
	printf '[+%ds] %s\n' "$((SECONDS - t0))" "$label"
	return $st
}

source "$ESSENTIALS_DIR/make.sh"
source "$ESSENTIALS_DIR/curl.sh"
source "$ESSENTIALS_DIR/chezmoi.sh"
source "$ESSENTIALS_DIR/flatpak.sh"
source "$ESSENTIALS_DIR/pulseaudio-utils.sh"
source "$ESSENTIALS_DIR/fuse.sh"
source "$ESSENTIALS_DIR/synaptic.sh"
source "$ESSENTIALS_DIR/python3/python3-pip.sh"
source "$ESSENTIALS_DIR/python3/python3-pipx.sh"

source "$DESKTOP_APPS_DIR/timeshift.sh"
source "$DESKTOP_APPS_DIR/fsearch.sh"
source "$DESKTOP_APPS_DIR/chrome.sh"
source "$DESKTOP_APPS_DIR/discord.sh"
source "$DESKTOP_APPS_DIR/obs/obs.sh"
source "$DESKTOP_APPS_DIR/obsidian.sh"
source "$DESKTOP_APPS_DIR/spotify.sh"
source "$DESKTOP_APPS_DIR/handy/handy.sh"
source "$DESKTOP_APPS_DIR/handy/handy-config.sh"

source "$DEVELOPMENT_DIR/git/git.sh"
source "$DEVELOPMENT_DIR/cursor.sh"
source "$DEVELOPMENT_DIR/gitkraken.sh"
source "$DEVELOPMENT_DIR/vscode.sh"
source "$DEVELOPMENT_DIR/fonts.sh"
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
step install_make
step install_curl
step install_chezmoi
step install_flatpak
step install_pulseaudio_utils
step install_fuse
step install_synaptic
step install_pip
step install_pipx

# Repositories (apt sources only, no installs, no apt update)
step install_fsearch_repository
step install_spotify_repository
step install_cursor_repository
step install_vscode_repository
step install_docker_repository
step install_beekeeper_studio_repository

# Single update covering all repositories above.
step apt_update sudo apt update

# Desktop Apps
step install_timeshift
step install_fsearch
step install_chrome
step install_discord
step install_obs
step install_obsidian
step install_spotify
step install_handy
step config_handy

# Development
step install_git
step install_cursor_cli
step install_cursor
step install_gitkraken
step install_vscode
step install_fonts
step install_docker
step install_postman
step install_beekeeper_studio
step install_zsh
step config_zsh
step install_zoxide
step install_opencode
step install_ghostty
step config_ghostty
step install_ollama

# Dotfiles identity (git user.name/email). Asked once, stored in
# ~/.config/chezmoi/chezmoi.toml so re-runs never prompt again.
# Non-interactive: CHEZMOI_NAME / CHEZMOI_EMAIL.
CHEZMOI_CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
if [[ ! -f $CHEZMOI_CONFIG ]]; then
	name=${CHEZMOI_NAME:-}
	email=${CHEZMOI_EMAIL:-}
	[[ -z $name ]] && read -rp "Git name: " name
	[[ -z $email ]] && read -rp "Git email: " email
	mkdir -p "$HOME/.config/chezmoi"
	printf '[data]\n\tname = "%s"\n\temail = "%s"\n' \
		"${name//\"/\\\"}" "${email//\"/\\\"}" >"$CHEZMOI_CONFIG"
fi

step chezmoi chezmoi apply --source "$DOTFILES_DIR"

step versions bash "$SCRIPT_DIR/../reports/versions.sh"

printf '[+%ds] install.sh total\n' "$((SECONDS - install_start))"