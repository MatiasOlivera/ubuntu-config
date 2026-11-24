#!/usr/bin/env bash

# Ask for sudo once up front and keep the timestamp alive for the whole run.
if ! sudo -n true 2>/dev/null; then
	if [[ ! -t 0 ]]; then
		printf 'error: sudo authentication required, run in an interactive terminal\n' >&2
		exit 1
	fi
	sudo -v || exit 1
fi
while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" || exit; done >/dev/null 2>&1 &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null' EXIT

SCRIPT_DIR=$(dirname "$0")
if [[ -n ${OBSERVABILITY_RECORD_DIR:-} ]]; then
	source "$SCRIPT_DIR/helpers/observability.sh"
	observability_init "${OBSERVABILITY_RUN_ID:-unknown}" "${OBSERVABILITY_COLLECTOR:-}" ||
		printf 'warning: e2e observability initialization failed\n' >&2
	observability_phase_begin post-install.sh
fi

# SKIP_UPGRADE=1 skips apt upgrade (fast path for test.sh --vm).
upgrade_start=$SECONDS
if [[ ${SKIP_UPGRADE:-0} != 1 ]]; then
  # check for updates
  sudo apt update

  # apply updates
  sudo apt upgrade -y
  printf '[+%ds] apt upgrade\n' "$((SECONDS - upgrade_start))"
fi

# ponytail: SECONDS wall-clock per step, no external profiler.
post_start=$SECONDS
source "$SCRIPT_DIR/helpers/steps.sh"

DEVELOPMENT_DIR="$SCRIPT_DIR/development"

source "$DEVELOPMENT_DIR/oh-my-zsh/oh-my-zsh.sh"
source "$DEVELOPMENT_DIR/oh-my-zsh/plugins.sh"
source "$DEVELOPMENT_DIR/oh-my-zsh/theme.sh"
source "$DEVELOPMENT_DIR/antigravity-cli.sh"
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
phase_status=0
[[ ${#FAILED_STEPS[@]} -gt 0 ]] && phase_status=1
observability_phase_end "$phase_status"
report_failed_steps || exit 1
