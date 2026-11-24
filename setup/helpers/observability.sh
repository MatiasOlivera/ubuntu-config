#!/usr/bin/env bash
# Source-only observability emitter for the Multipass e2e run.
# No-op until observability_init is called; normal setup runs keep their exact behavior.

OBSERVABILITY_INITIALIZED=0
OBSERVABILITY_TRACE_ID=
OBSERVABILITY_SPAN_SEQ=0
OBSERVABILITY_FORWARD_WARNED=0
OBSERVABILITY_REAL_CURL=
OBSERVABILITY_STEP_NET_BEFORE=0
OBSERVABILITY_NEXT_SPAN_ID=

observability_repo_root() {
	cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

observability_json_escape() {
	local s=$1
	s=${s//\\/\\\\}
	s=${s//\"/\\\"}
	printf '%s' "$s"
}

observability_enabled() {
	[[ $OBSERVABILITY_INITIALIZED -eq 1 ]]
}

observability_warn_once() {
	[[ $OBSERVABILITY_FORWARD_WARNED -eq 1 ]] && return 0
	OBSERVABILITY_FORWARD_WARNED=1
	printf 'warning: live observability forwarding unavailable\n' >&2
}

observability_init() {
	OBSERVABILITY_RUN_ID=$1
	OBSERVABILITY_COLLECTOR=${2:-}
	[[ -n ${OBSERVABILITY_RECORD_DIR:-} ]] || return 1
	mkdir -p "$OBSERVABILITY_RECORD_DIR/logs" || return 1
	printf -v OBSERVABILITY_TRACE_ID '%04x%04x%04x%04x%04x%04x%04x%04x' \
		"$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" \
		"$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM"
	OBSERVABILITY_REAL_CURL=${OBSERVABILITY_E2E_REAL_CURL:-$(command -v curl 2>/dev/null || true)}
	local helper
	helper="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/observability.sh"

	export OBSERVABILITY_E2E_TRACE_ID=$OBSERVABILITY_TRACE_ID
	export OBSERVABILITY_E2E_RUN_ID=$OBSERVABILITY_RUN_ID
	export OBSERVABILITY_E2E_PHASE=${OBSERVABILITY_PHASE:-}
	export OBSERVABILITY_E2E_RECORD_DIR=$OBSERVABILITY_RECORD_DIR
	export OBSERVABILITY_E2E_COLLECTOR=$OBSERVABILITY_COLLECTOR
	export OBSERVABILITY_E2E_HELPER=${OBSERVABILITY_E2E_HELPER:-$helper}
	export OBSERVABILITY_E2E_REAL_CURL=$OBSERVABILITY_REAL_CURL
	export OBSERVABILITY_E2E_REAL_WGET=${OBSERVABILITY_E2E_REAL_WGET:-$(command -v wget 2>/dev/null || true)}
	export OBSERVABILITY_E2E_REAL_GIT=${OBSERVABILITY_E2E_REAL_GIT:-$(command -v git 2>/dev/null || true)}
	export OBSERVABILITY_E2E_REAL_SUDO=${OBSERVABILITY_E2E_REAL_SUDO:-$(command -v sudo 2>/dev/null || true)}
	observability_install_shims

	local -a meta=()
	meta+=("\"run_id\":\"$(observability_json_escape "$OBSERVABILITY_RUN_ID")\"")
	meta+=("\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"")
	meta+=("\"git_sha\":\"$(observability_json_escape "${OBSERVABILITY_GIT_SHA:-}")\"")
	meta+=("\"git_branch\":\"$(observability_json_escape "${OBSERVABILITY_GIT_BRANCH:-}")\"")
	meta+=("\"vm_name\":\"$(observability_json_escape "${OBSERVABILITY_VM_NAME:-}")\"")
	meta+=("\"ubuntu_image\":\"$(observability_json_escape "${OBSERVABILITY_IMAGE:-}")\"")
	printf '{%s}\n' "$(IFS=,; printf '%s' "${meta[*]}")" > "$OBSERVABILITY_RECORD_DIR/run.json"

	OBSERVABILITY_INITIALIZED=1
}

observability_install_shims() {
	local src_dir dest name
	src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/observability-shims"
	dest="$OBSERVABILITY_RECORD_DIR/shims"
	mkdir -p "$dest" || return 1
	for f in "$src_dir"/*.sh; do
		cp "$f" "$dest/" || return 1
	done
	for name in curl wget git sudo; do
		cp "$dest/$name.sh" "$dest/$name" || return 1
		chmod +x "$dest/$name" || return 1
	done
	export PATH="$dest:$PATH"
}

observability_net_bytes() {
	local dev=${OBSERVABILITY_E2E_NET_DEV:-/proc/net/dev}
	awk 'NR > 2 { gsub(/:/, "", $1); sum += $2 + $10 } END { printf "%d", sum + 0 }' \
		"$dev" 2>/dev/null || printf '0'
}

observability_restore() {
	OBSERVABILITY_INITIALIZED=1
	OBSERVABILITY_TRACE_ID=${OBSERVABILITY_E2E_TRACE_ID:-}
	OBSERVABILITY_RUN_ID=${OBSERVABILITY_E2E_RUN_ID:-}
	OBSERVABILITY_COLLECTOR=${OBSERVABILITY_E2E_COLLECTOR:-}
	OBSERVABILITY_PHASE=${OBSERVABILITY_E2E_PHASE:-}
	OBSERVABILITY_REAL_CURL=${OBSERVABILITY_E2E_REAL_CURL:-}
}

observability_emit_child() {
	# kind name start end status exit_code attributes_json url_host
	local extra=
	if [[ -n ${8:-} ]]; then
		printf -v extra ',"url_host":"%s"' "$(observability_json_escape "$8")"
	fi
	observability_span "$2" "$1" "$3" "$4" "$5" "$6" "" "$7" "${OBSERVABILITY_E2E_PARENT_SPAN:-}" "$extra"
}

observability_check_manifest() {
	local file=$1 root label paths path rc=0
	root="$(observability_repo_root)"
	while IFS=$'\t' read -r label paths; do
		[[ -z $label || $label == \#* ]] && continue
		if ! grep -qE "^(step|advisory_step) +['\"]?${label}([[:space:]]|\$)" \
			"$root/setup/install.sh" "$root/setup/post-install.sh"; then
			printf '%s: not a step label\n' "$label" >&2
			rc=1
		fi
		for path in $paths; do
			case $path in
			\$HOME/*|/usr/local/*|/opt/*|/var/lib/*|/snap/*|/home/linuxbrew/*) ;;
			*)
				printf '%s: path outside allowed roots\n' "$path" >&2
				rc=1
				;;
			esac
		done
	done < "$file"
	return $rc
}

observability_disk_bytes() {
	local label=$1 manifest=${2:-${OBSERVABILITY_E2E_APP_PATHS:-}} paths path n total=0
	export OBSERVABILITY_DISK_BASIS=approximate
	[[ -n $manifest && -f $manifest ]] || {
		printf '0\n'
		return 0
	}
	paths=$(awk -F'\t' -v l="$label" '$1 == l { print $2 }' "$manifest")
	for path in $paths; do
		path=${path//\$HOME/$HOME}
		if [[ -e $path ]]; then
			n=$(du -sb "$path" 2>/dev/null | awk '{ print $1 }')
			total=$((total + ${n:-0}))
		fi
	done
	printf '%d\n' "$total"
}

observability_pkg_snapshot() {
	local out=$1 query=${OBSERVABILITY_E2E_DPKG_QUERY:-dpkg-query}
	# shellcheck disable=SC2016 # the dpkg-query format is intentionally literal
	"$query" -W -f='${binary:Package}\t${Installed-Size}\n' 2>/dev/null |
		awk -F'\t' 'NF >= 2 { print $1 "\t" $2 }' > "$out"
}

observability_pkg_delta() {
	awk -F'\t' 'NR == FNR { seen[$1] = 1; next } !($1 in seen) { sum += $2 }
		END { printf "%d", sum + 0 }' "$1" "$2"
}

observability_step_begin() {
	observability_enabled || return 0
	OBSERVABILITY_SPAN_SEQ=$((OBSERVABILITY_SPAN_SEQ + 1))
	local label
	printf -v label '%04x%04x%04x%04x' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM"
	OBSERVABILITY_CURRENT_SPAN=$label
	OBSERVABILITY_NEXT_SPAN_ID=$label
	export OBSERVABILITY_PARENT_SPAN=$label
	export OBSERVABILITY_E2E_PARENT_SPAN=$label
	OBSERVABILITY_CURRENT_LABEL=$1
	OBSERVABILITY_CURRENT_START=$(date +%s%N)
	OBSERVABILITY_STEP_NET_BEFORE=$(observability_net_bytes)
	OBSERVABILITY_CURRENT_LOG="$OBSERVABILITY_RECORD_DIR/logs/$label.log"
	: > "$OBSERVABILITY_CURRENT_LOG"
}

observability_forward() {
	# trace_id span_id name start_ns end_ns otlp_status attributes_json
	[[ -n ${OBSERVABILITY_COLLECTOR:-} && -n $OBSERVABILITY_REAL_CURL ]] || return 0
	local payload
	printf -v payload '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"ubuntu-config-e2e"}}]},"scopeSpans":[{"spans":[{"traceId":"%s","spanId":"%s","name":"%s","startTimeUnixNano":"%s","endTimeUnixNano":"%s","status":{"code":%s},"attributes":%s}]}]}]}' \
		"$1" "$2" "$(observability_json_escape "$3")" "$4" "$5" "$6" "$7"
	"$OBSERVABILITY_REAL_CURL" -sS --max-time 2 -X POST \
		-H 'Content-Type: application/json' \
		"$OBSERVABILITY_COLLECTOR/v1/traces" -d "$payload" >/dev/null 2>&1 || observability_warn_once
}

observability_span() {
	# name kind start_ns end_ns status exit_code log_ref attributes_json [parent] [extra_top_level_json]
	observability_enabled || return 0
	local name=$1 kind=$2 start=$3 end=$4 status=$5 exit_code=$6 log_ref=$7 attrs=$8 parent=${9:-} extra=${10:-}
	local span_id duration_ms escaped_name otlp_status
	if [[ -n $OBSERVABILITY_NEXT_SPAN_ID ]]; then
		span_id=$OBSERVABILITY_NEXT_SPAN_ID
		OBSERVABILITY_NEXT_SPAN_ID=
	else
		printf -v span_id '%04x%04x%04x%04x' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM"
	fi
	duration_ms=$(((end - start) / 1000000))
	escaped_name="$(observability_json_escape "$name")"
	printf '{"trace_id":"%s","span_id":"%s","parent_span_id":"%s","name":"%s","kind":"%s","phase":"%s","start_ns":%s,"end_ns":%s,"duration_ms":%s,"status":"%s","exit_code":%s,"log_ref":"%s","run_id":"%s","attributes":%s%s}\n' \
		"$OBSERVABILITY_TRACE_ID" "$span_id" "$parent" "$escaped_name" "$kind" \
		"$(observability_json_escape "${OBSERVABILITY_PHASE:-}")" "$start" "$end" "$duration_ms" \
		"$(observability_json_escape "$status")" "$exit_code" "$(observability_json_escape "$log_ref")" \
		"$(observability_json_escape "$OBSERVABILITY_RUN_ID")" "$attrs" "$extra" >> "$OBSERVABILITY_RECORD_DIR/spans.jsonl"
	otlp_status=1
	[[ $status == ok ]] || otlp_status=2
	observability_forward "$OBSERVABILITY_TRACE_ID" "$span_id" "$name" "$start" "$end" "$otlp_status" "$attrs"
}

observability_step_end() {
	observability_enabled || return 0
	local end status
	end=$(date +%s%N)
	if [[ $1 -eq 0 ]]; then
		status=ok
	else
		status=error
	fi
	local attrs net_bytes disk_bytes
	net_bytes=$(($(observability_net_bytes) - OBSERVABILITY_STEP_NET_BEFORE))
	disk_bytes=$(observability_disk_bytes "$OBSERVABILITY_CURRENT_LABEL")
	printf -v attrs '[{"key":"app","value":{"stringValue":"%s"}},{"key":"phase","value":{"stringValue":"%s"}},{"key":"run_id","value":{"stringValue":"%s"}},{"key":"exit_code","value":{"intValue":%s}},{"key":"bytes_net_approx","value":{"intValue":%s}},{"key":"bytes_disk_approx","value":{"intValue":%s}}]' \
		"$(observability_json_escape "$OBSERVABILITY_CURRENT_LABEL")" \
		"$(observability_json_escape "${OBSERVABILITY_PHASE:-}")" \
		"$(observability_json_escape "$OBSERVABILITY_RUN_ID")" "$1" "$net_bytes" "$disk_bytes"
	observability_span "$OBSERVABILITY_CURRENT_LABEL" step "$OBSERVABILITY_CURRENT_START" "$end" \
		"$status" "$1" "logs/$OBSERVABILITY_CURRENT_SPAN.log" "$attrs"
}

# Phase totals: one root span per setup phase. The start is captured even before
# observability_init so callers can place the call at their existing total timer.
observability_phase_begin() {
	OBSERVABILITY_PHASE_START=$(date +%s%N)
	OBSERVABILITY_PHASE_LABEL=${1:-}
	observability_enabled || return 0
}

observability_phase_end() {
	observability_enabled || return 0
	[[ -n ${OBSERVABILITY_PHASE_START:-} ]] || return 0
	local end status code attrs
	end=$(date +%s%N)
	code=${1:-0}
	if [[ $code -eq 0 ]]; then status=ok; else status=error; fi
	printf -v attrs '[{"key":"app","value":{"stringValue":"%s"}},{"key":"phase","value":{"stringValue":"%s"}},{"key":"run_id","value":{"stringValue":"%s"}},{"key":"exit_code","value":{"intValue":%s}}]' \
		"$(observability_json_escape "$OBSERVABILITY_PHASE_LABEL")" \
		"$(observability_json_escape "${OBSERVABILITY_PHASE:-}")" \
		"$(observability_json_escape "$OBSERVABILITY_RUN_ID")" "$code"
	observability_span "$OBSERVABILITY_PHASE_LABEL" phase "$OBSERVABILITY_PHASE_START" "$end" \
		"$status" "$code" "" "$attrs"
	OBSERVABILITY_PHASE_START=
}
