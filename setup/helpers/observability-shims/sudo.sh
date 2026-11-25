#!/usr/bin/env bash
# [Architecture] Uses Proxy
# shellcheck disable=SC1091 # common.sh lives beside the installed shim
source "$(dirname "$0")/common.sh"
case ${1:-} in
apt | apt-get | snap | flatpak)
	observability_shim_run package-manager "$1" "$OBSERVABILITY_E2E_REAL_SUDO" "$@"
	exit $?
	;;
*)
	# Keepalive and unrelated sudo calls are not install work.
	exec "$OBSERVABILITY_E2E_REAL_SUDO" "$@"
	;;
esac
