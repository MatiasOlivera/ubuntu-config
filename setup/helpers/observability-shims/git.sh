#!/usr/bin/env bash
# shellcheck disable=SC1091 # common.sh lives beside the installed shim
source "$(dirname "$0")/common.sh"
if [[ ${1:-} == clone ]]; then
	observability_shim_run download git "$OBSERVABILITY_E2E_REAL_GIT" "$@"
	exit $?
fi
exec "$OBSERVABILITY_E2E_REAL_GIT" "$@"
