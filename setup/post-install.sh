#!/usr/bin/env bash

# SKIP_UPGRADE=1 skips apt upgrade (fast path for test.sh --vm).
if [[ ${SKIP_UPGRADE:-0} != 1 ]]; then
  # check for updates
  sudo apt update

  # apply updates
  sudo apt upgrade -y
fi

SCRIPT_DIR=$(dirname "$0")

DEVELOPMENT_DIR="$SCRIPT_DIR/development"

source "$DEVELOPMENT_DIR/oh-my-zsh/oh-my-zsh.sh"
source "$DEVELOPMENT_DIR/oh-my-zsh/plugins.sh"
source "$DEVELOPMENT_DIR/oh-my-zsh/theme.sh"
source "$DEVELOPMENT_DIR/antigravity-cli/antigravity-cli.sh"
source "$DEVELOPMENT_DIR/fnm/install-fnm.sh"
source "$DEVELOPMENT_DIR/fnm/fnm-config.sh"

# Development
install_oh_my_zsh
install_oh_my_zsh_plugins
install_oh_my_zsh_theme
install_antigravity_cli
install_fnm
config_fnm

bash "$SCRIPT_DIR/../tests/verify.sh" || true
