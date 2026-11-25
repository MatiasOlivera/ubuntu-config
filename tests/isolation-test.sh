#!/usr/bin/env bash
# isolation-test.sh — assert the code-executing tier stays hardened (ADR 0006).
# Contract-only: reads config files, runs no container and makes no requests.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
status=0

check() {
	local label=$1 file=$2 pattern=$3
	if grep -qE -- "$pattern" "$root/$file"; then
		printf 'ok: %s\n' "$label"
	else
		printf 'FAIL: %s\n' "$label" >&2
		status=1
	fi
}

check_absent() {
	local label=$1 file=$2 pattern=$3
	if grep -qE -- "$pattern" "$root/$file"; then
		printf 'FAIL: %s\n' "$label" >&2
		status=1
	else
		printf 'ok: %s\n' "$label"
	fi
}

check 'compose drops capabilities' tests/compose.yml '^[[:space:]]*cap_drop:'
check 'compose drops ALL' tests/compose.yml '^[[:space:]]*-[[:space:]]+ALL[[:space:]]*$'
check 'compose forbids new privileges' tests/compose.yml 'no-new-privileges'
check 'compose has no network' tests/compose.yml '^[[:space:]]*network_mode:[[:space:]]*none[[:space:]]*$'
check 'compose mounts checkout read-only' tests/compose.yml '/work:ro'

workflow=.github/workflows/test-image.yml
check "$workflow drops capabilities" "$workflow" --cap-drop=ALL
check "$workflow forbids new privileges" "$workflow" --security-opt=no-new-privileges
check "$workflow has no network" "$workflow" --network=none
check "$workflow mounts checkout read-only" "$workflow" /work:ro

gate=.github/workflows/test.yml
check_absent 'gate has no image-mode selection' "$gate" ci-image-mode
check_absent 'gate has no published-image reference' "$gate" TEST_IMAGE
check_absent 'gate does not pull an image' "$gate" 'docker pull'
check 'gate builds from the checkout' "$gate" 'docker compose -f tests/compose.yml run --rm test'

exit "$status"
