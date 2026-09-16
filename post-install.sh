#!/usr/bin/env bash

# check for updates
sudo apt update

# apply updates
sudo apt upgrade -y

SCRIPT_DIR=$(dirname "$0")

DEVELOPMENT_DIR="$SCRIPT_DIR/development"

source "$DEVELOPMENT_DIR/oh-my-zsh/oh-my-zsh.sh"
source "$DEVELOPMENT_DIR/oh-my-zsh/plugins.sh"
source "$DEVELOPMENT_DIR/oh-my-zsh/theme.sh"
source "$DEVELOPMENT_DIR/antigravity-cli/antigravity-cli.sh"
source "$DEVELOPMENT_DIR/antigravity-cli/antigravity-cli-config.sh"
source "$DEVELOPMENT_DIR/fnm/install-fnm.sh"

# Development
install_oh_my_zsh
install_oh_my_zsh_plugins
install_oh_my_zsh_theme
install_antigravity_cli
configure_antigravity_cli
install_fnm
