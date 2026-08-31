#!/bin/sh

# check for updates
sudo apt update

# apply updates
sudo apt upgrade

DEVELOPMENT_DIR="$SCRIPT_DIR/development"

source "$DEVELOPMENT_DIR/oh-my-zsh/oh-myzsh.sh"

# Development
install_oh_my_zsh
