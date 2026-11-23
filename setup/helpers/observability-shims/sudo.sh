#!/usr/bin/env bash
# shellcheck disable=SC1091 # common.sh lives beside the installed shim
source "$(dirname "$0")/common.sh"
case ${1:-} in
apt | apt-get | snap | flatpak)
	obs_shim_run package-manager "$1" "$OBS_E2E_REAL_SUDO" "$@"
	exit $?
	;;
*)
	# Keepalive and unrelated sudo calls are not install work.
	exec "$OBS_E2E_REAL_SUDO" "$@"
	;;
esac
