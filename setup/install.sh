#!/usr/bin/env bash

SCRIPT_DIR=$(dirname "$0")

ESSENTIALS_DIR="$SCRIPT_DIR/essentials"
DESKTOP_APPS_DIR="$SCRIPT_DIR/desktop-apps"
DEVELOPMENT_DIR="$SCRIPT_DIR/development"
DOTFILES_DIR="$SCRIPT_DIR/../dotfiles"

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
install_make
install_curl
install_chezmoi
install_flatpak
install_pulseaudio_utils
install_fuse
install_synaptic
install_pip
install_pipx

# Repositories (apt sources only, no installs, no apt update)
install_fsearch_repository
install_spotify_repository
install_cursor_repository
install_vscode_repository
install_docker_repository
install_beekeeper_studio_repository

# Single update covering all repositories above.
sudo apt update

# Desktop Apps
install_timeshift
install_fsearch
install_chrome
install_discord
install_obs
install_obsidian
install_spotify
install_handy
config_handy

# Development
install_git
install_cursor_cli
install_cursor
install_gitkraken
install_vscode
install_fonts
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

chezmoi apply --source "$DOTFILES_DIR"

bash "$SCRIPT_DIR/../tests/verify.sh"