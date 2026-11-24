#!/usr/bin/env bash
# [Architecture] Uses Proxy
# shellcheck disable=SC1091 # common.sh lives beside the installed shim
source "$(dirname "$0")/common.sh"
observability_shim_run download wget "$OBSERVABILITY_E2E_REAL_WGET" "$@"
exit $?
