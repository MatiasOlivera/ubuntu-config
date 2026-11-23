#!/usr/bin/env bash
# Source-only observability emitter for the Multipass e2e run.
# No-op until obs_init is called; normal setup runs keep their exact behavior.

OBS_INITIALIZED=0
OBS_TRACE_ID=
OBS_SPAN_SEQ=0
OBS_FORWARD_WARNED=0
OBS_REAL_CURL=
OBS_STEP_NET_BEFORE=0
OBS_NEXT_SPAN_ID=

obs_repo_root() {
	cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

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
	OBS_REAL_CURL=${OBS_E2E_REAL_CURL:-$(command -v curl 2>/dev/null || true)}
	local helper
	helper="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/observability.sh"

	export OBS_E2E_TRACE_ID=$OBS_TRACE_ID
	export OBS_E2E_RUN_ID=$OBS_RUN_ID
	export OBS_E2E_PHASE=${OBS_PHASE:-}
	export OBS_E2E_RECORD_DIR=$OBS_RECORD_DIR
	export OBS_E2E_COLLECTOR=$OBS_COLLECTOR
	export OBS_E2E_HELPER=${OBS_E2E_HELPER:-$helper}
	export OBS_E2E_REAL_CURL=$OBS_REAL_CURL
	export OBS_E2E_REAL_WGET=${OBS_E2E_REAL_WGET:-$(command -v wget 2>/dev/null || true)}
	export OBS_E2E_REAL_GIT=${OBS_E2E_REAL_GIT:-$(command -v git 2>/dev/null || true)}
	export OBS_E2E_REAL_SUDO=${OBS_E2E_REAL_SUDO:-$(command -v sudo 2>/dev/null || true)}
	obs_install_shims

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

obs_install_shims() {
	local src_dir dest name
	src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/observability-shims"
	dest="$OBS_RECORD_DIR/shims"
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

obs_net_bytes() {
	local dev=${OBS_E2E_NET_DEV:-/proc/net/dev}
	awk 'NR > 2 { gsub(/:/, "", $1); sum += $2 + $10 } END { printf "%d", sum + 0 }' \
		"$dev" 2>/dev/null || printf '0'
}

obs_restore() {
	OBS_INITIALIZED=1
	OBS_TRACE_ID=${OBS_E2E_TRACE_ID:-}
	OBS_RUN_ID=${OBS_E2E_RUN_ID:-}
	OBS_COLLECTOR=${OBS_E2E_COLLECTOR:-}
	OBS_PHASE=${OBS_E2E_PHASE:-}
	OBS_REAL_CURL=${OBS_E2E_REAL_CURL:-}
}

obs_emit_child() {
	# kind name start end status exit_code attributes_json
	obs_span "$2" "$1" "$3" "$4" "$5" "$6" "" "$7" "${OBS_E2E_PARENT_SPAN:-}"
}

obs_check_manifest() {
	local file=$1 root label paths path rc=0
	root="$(obs_repo_root)"
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

obs_disk_bytes() {
	local label=$1 manifest=${2:-${OBS_E2E_APP_PATHS:-}} paths path n total=0
	export OBS_DISK_BASIS=approximate
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

obs_pkg_snapshot() {
	local out=$1 query=${OBS_E2E_DPKG_QUERY:-dpkg-query}
	# shellcheck disable=SC2016 # the dpkg-query format is intentionally literal
	"$query" -W -f='${binary:Package}\t${Installed-Size}\n' 2>/dev/null |
		awk -F'\t' 'NF >= 2 { print $1 "\t" $2 }' > "$out"
}

obs_pkg_delta() {
	awk -F'\t' 'NR == FNR { seen[$1] = 1; next } !($1 in seen) { sum += $2 }
		END { printf "%d", sum + 0 }' "$1" "$2"
}

obs_step_begin() {
	obs_enabled || return 0
	OBS_SPAN_SEQ=$((OBS_SPAN_SEQ + 1))
	local label
	printf -v label '%04x%04x%04x%04x' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM"
	OBS_CURRENT_SPAN=$label
	OBS_NEXT_SPAN_ID=$label
	export OBS_PARENT_SPAN=$label
	export OBS_E2E_PARENT_SPAN=$label
	OBS_CURRENT_LABEL=$1
	OBS_CURRENT_START=$(date +%s%N)
	OBS_STEP_NET_BEFORE=$(obs_net_bytes)
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
	if [[ -n $OBS_NEXT_SPAN_ID ]]; then
		span_id=$OBS_NEXT_SPAN_ID
		OBS_NEXT_SPAN_ID=
	else
		printf -v span_id '%04x%04x%04x%04x' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM"
	fi
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
	local attrs net_bytes disk_bytes
	net_bytes=$(($(obs_net_bytes) - OBS_STEP_NET_BEFORE))
	disk_bytes=$(obs_disk_bytes "$OBS_CURRENT_LABEL")
	printf -v attrs '[{"key":"app","value":{"stringValue":"%s"}},{"key":"phase","value":{"stringValue":"%s"}},{"key":"run_id","value":{"stringValue":"%s"}},{"key":"exit_code","value":{"intValue":%s}},{"key":"bytes_net_approx","value":{"intValue":%s}},{"key":"bytes_disk_approx","value":{"intValue":%s}}]' \
		"$(obs_json_escape "$OBS_CURRENT_LABEL")" \
		"$(obs_json_escape "${OBS_PHASE:-}")" \
		"$(obs_json_escape "$OBS_RUN_ID")" "$1" "$net_bytes" "$disk_bytes"
	obs_span "$OBS_CURRENT_LABEL" step "$OBS_CURRENT_START" "$end" \
		"$status" "$1" "logs/$OBS_CURRENT_SPAN.log" "$attrs"
}
