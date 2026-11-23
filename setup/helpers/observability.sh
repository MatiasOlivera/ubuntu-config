#!/usr/bin/env bash
# Source-only observability emitter for the Multipass e2e run.
# No-op until obs_init is called; normal setup runs keep their exact behavior.

OBS_INITIALIZED=0
OBS_TRACE_ID=
OBS_SPAN_SEQ=0
OBS_FORWARD_WARNED=0
OBS_REAL_CURL=

obs_json_escape() {
	local s=$1
	s=${s//\\/\\\\}
	s=${s//\"/\\\"}
	printf '%s' "$s"
}

obs_enabled() {
	[[ $OBS_INITIALIZED -eq 1 ]]
}

obs_warn_once() {
	[[ $OBS_FORWARD_WARNED -eq 1 ]] && return 0
	OBS_FORWARD_WARNED=1
	printf 'warning: live observability forwarding unavailable\n' >&2
}

obs_init() {
	OBS_RUN_ID=$1
	OBS_COLLECTOR=${2:-}
	[[ -n ${OBS_RECORD_DIR:-} ]] || return 1
	mkdir -p "$OBS_RECORD_DIR/logs" || return 1
	printf -v OBS_TRACE_ID '%04x%04x%04x%04x%04x%04x%04x%04x' \
		"$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" \
		"$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM"
	OBS_REAL_CURL="$(command -v curl 2>/dev/null || true)"

	local -a meta=()
	meta+=("\"run_id\":\"$(obs_json_escape "$OBS_RUN_ID")\"")
	meta+=("\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"")
	meta+=("\"git_sha\":\"$(obs_json_escape "${OBS_GIT_SHA:-}")\"")
	meta+=("\"git_branch\":\"$(obs_json_escape "${OBS_GIT_BRANCH:-}")\"")
	meta+=("\"vm_name\":\"$(obs_json_escape "${OBS_VM_NAME:-}")\"")
	meta+=("\"ubuntu_image\":\"$(obs_json_escape "${OBS_IMAGE:-}")\"")
	printf '{%s}\n' "$(IFS=,; printf '%s' "${meta[*]}")" > "$OBS_RECORD_DIR/run.json"

	OBS_INITIALIZED=1
}

obs_step_begin() {
	obs_enabled || return 0
	OBS_SPAN_SEQ=$((OBS_SPAN_SEQ + 1))
	local label
	printf -v label '%04x%04x%04x%04x' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM"
	OBS_CURRENT_SPAN=$label
	export OBS_PARENT_SPAN=$label
	OBS_CURRENT_LABEL=$1
	OBS_CURRENT_START=$(date +%s%N)
	OBS_CURRENT_LOG="$OBS_RECORD_DIR/logs/$label.log"
	: > "$OBS_CURRENT_LOG"
}

obs_forward() {
	# trace_id span_id name start_ns end_ns otlp_status attributes_json
	[[ -n ${OBS_COLLECTOR:-} && -n $OBS_REAL_CURL ]] || return 0
	local payload
	printf -v payload '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"ubuntu-config-e2e"}}]},"scopeSpans":[{"spans":[{"traceId":"%s","spanId":"%s","name":"%s","startTimeUnixNano":"%s","endTimeUnixNano":"%s","status":{"code":%s},"attributes":%s}]}]}]}' \
		"$1" "$2" "$(obs_json_escape "$3")" "$4" "$5" "$6" "$7"
	"$OBS_REAL_CURL" -sS --max-time 2 -X POST \
		-H 'Content-Type: application/json' \
		"$OBS_COLLECTOR/v1/traces" -d "$payload" >/dev/null 2>&1 || obs_warn_once
}

obs_span() {
	# name kind start_ns end_ns status exit_code log_ref attributes_json [parent]
	obs_enabled || return 0
	local name=$1 kind=$2 start=$3 end=$4 status=$5 exit_code=$6 log_ref=$7 attrs=$8 parent=${9:-}
	local span_id duration_ms escaped_name otlp_status
	printf -v span_id '%04x%04x%04x%04x' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM"
	duration_ms=$(((end - start) / 1000000))
	escaped_name="$(obs_json_escape "$name")"
	printf '{"trace_id":"%s","span_id":"%s","parent_span_id":"%s","name":"%s","kind":"%s","phase":"%s","start_ns":%s,"end_ns":%s,"duration_ms":%s,"status":"%s","exit_code":%s,"log_ref":"%s","run_id":"%s","attributes":%s}\n' \
		"$OBS_TRACE_ID" "$span_id" "$parent" "$escaped_name" "$kind" \
		"$(obs_json_escape "${OBS_PHASE:-}")" "$start" "$end" "$duration_ms" \
		"$(obs_json_escape "$status")" "$exit_code" "$(obs_json_escape "$log_ref")" \
		"$(obs_json_escape "$OBS_RUN_ID")" "$attrs" >> "$OBS_RECORD_DIR/spans.jsonl"
	otlp_status=1
	[[ $status == ok ]] || otlp_status=2
	obs_forward "$OBS_TRACE_ID" "$span_id" "$name" "$start" "$end" "$otlp_status" "$attrs"
}

obs_step_end() {
	obs_enabled || return 0
	local end status
	end=$(date +%s%N)
	if [[ $1 -eq 0 ]]; then
		status=ok
	else
		status=error
	fi
	local attrs
	printf -v attrs '[{"key":"app","value":{"stringValue":"%s"}},{"key":"phase","value":{"stringValue":"%s"}},{"key":"run_id","value":{"stringValue":"%s"}},{"key":"exit_code","value":{"intValue":%s}},{"key":"bytes_net_approx","value":{"intValue":0}},{"key":"bytes_disk_approx","value":{"intValue":0}}]' \
		"$(obs_json_escape "$OBS_CURRENT_LABEL")" \
		"$(obs_json_escape "${OBS_PHASE:-}")" \
		"$(obs_json_escape "$OBS_RUN_ID")" "$1"
	obs_span "$OBS_CURRENT_LABEL" step "$OBS_CURRENT_START" "$end" \
		"$status" "$1" "logs/$OBS_CURRENT_SPAN.log" "$attrs"
}
