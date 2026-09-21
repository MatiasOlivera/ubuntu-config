#!/usr/bin/env bash

# SKIP_UPGRADE=1 skips apt upgrade (fast path for test.sh --vm).
upgrade_start=$SECONDS
if [[ ${SKIP_UPGRADE:-0} != 1 ]]; then
  # check for updates
  sudo apt update

  # apply updates
  sudo apt upgrade -y
  printf '[+%ds] apt upgrade\n' "$((SECONDS - upgrade_start))"
fi

SCRIPT_DIR=$(dirname "$0")

# ponytail: SECONDS wall-clock per step, no external profiler.
post_start=$SECONDS
step() {
  local label=$1
  local t0=$SECONDS
  if [[ $# -gt 1 ]]; then shift; fi
  "$@"
  local st=$?
  printf '[+%ds] %s\n' "$((SECONDS - t0))" "$label"
  return $st
}

DEVELOPMENT_DIR="$SCRIPT_DIR/development"

source "$DEVELOPMENT_DIR/oh-my-zsh/oh-my-zsh.sh"
source "$DEVELOPMENT_DIR/oh-my-zsh/plugins.sh"
source "$DEVELOPMENT_DIR/oh-my-zsh/theme.sh"
source "$DEVELOPMENT_DIR/antigravity-cli/antigravity-cli.sh"
source "$DEVELOPMENT_DIR/fnm/install-fnm.sh"
source "$DEVELOPMENT_DIR/fnm/fnm-config.sh"

# Development
step install_oh_my_zsh
step install_oh_my_zsh_plugins
step install_oh_my_zsh_theme
step install_antigravity_cli
step install_fnm
step config_fnm

step versions bash "$SCRIPT_DIR/../reports/versions.sh"

printf '[+%ds] post-install.sh total\n' "$((SECONDS - post_start))"
