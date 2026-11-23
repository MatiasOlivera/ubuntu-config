#!/usr/bin/env bash
# shellcheck disable=SC1091 # common.sh lives beside the installed shim
source "$(dirname "$0")/common.sh"
obs_shim_run download wget "$OBS_E2E_REAL_WGET" "$@"
exit $?
