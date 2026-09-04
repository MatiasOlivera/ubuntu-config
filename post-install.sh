#!/bin/sh

# check for updates
sudo apt update

# apply updates
sudo apt upgrade

DEVELOPMENT_DIR="$SCRIPT_DIR/development"

source "$DEVELOPMENT_DIR/oh-my-zsh/oh-myzsh.sh"
source "$DEVELOPMENT_DIR/oh-my-zsh/plugins.sh"
source "$DEVELOPMENT_DIR/oh-my-zsh/theme.sh"

# Development
install_oh_my_zsh
install_oh_my_zsh_plugins
install_oh_my_zsh_theme