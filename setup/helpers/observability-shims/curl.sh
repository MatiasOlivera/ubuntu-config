#!/usr/bin/env bash
# [Architecture] Uses Proxy
# shellcheck disable=SC1091 # common.sh lives beside the installed shim
source "$(dirname "$0")/common.sh"
observability_shim_run download curl "$OBSERVABILITY_E2E_REAL_CURL" "$@"
exit $?
