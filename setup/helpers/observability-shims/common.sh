#!/usr/bin/env bash
# Shared implementation for e2e observability PATH shims.

# shellcheck disable=SC1090 # helper path is exported by observability_init
source "$OBSERVABILITY_E2E_HELPER"
observability_restore

observability_shim_run() {
	local kind=$1 name=$2 real=$3
	shift 3
	local start end net_before net_after st status attrs host='' arg bundled=direct
	for arg in "$@"; do
		if [[ $arg == http://* || $arg == https://* ]]; then
			host=${arg#*://}
			host=${host%%/*}
			host=${host%%:*}
			break
		fi
	done
	[[ $kind == package-manager ]] && bundled=bundled
	start=$(date +%s%N)
	net_before=$(observability_net_bytes)
	"$real" "$@"
	st=$?
	end=$(date +%s%N)
	net_after=$(observability_net_bytes)
	if [[ $st -eq 0 ]]; then status=ok; else status=error; fi
	printf -v attrs '[{"key":"url_host","value":{"stringValue":"%s"}},{"key":"bytes_net_approx","value":{"intValue":%s}},{"key":"download_and_install","value":{"stringValue":"%s"}}]' \
		"$(observability_json_escape "$host")" "$((net_after - net_before))" "$bundled"
	observability_emit_child "$kind" "$name" "$start" "$end" "$status" "$st" "$attrs"
	return $st
}
