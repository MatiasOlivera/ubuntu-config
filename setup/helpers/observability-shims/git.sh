#!/usr/bin/env bash
# shellcheck disable=SC1091 # common.sh lives beside the installed shim
source "$(dirname "$0")/common.sh"
if [[ ${1:-} == clone ]]; then
	obs_shim_run download git "$OBS_E2E_REAL_GIT" "$@"
	exit $?
fi
exec "$OBS_E2E_REAL_GIT" "$@"
