#!/usr/bin/env bash
#
# version-paths-test.sh — version checks must find per-user installs without
# relying on an interactive shell's PATH. Hermetic: fake binaries in a temp HOME.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
export HOME="$T"
# Exclude host installations so only the fake per-user binaries can be found.
export PATH=/usr/bin:/bin

mkdir -p "$T/.opencode/bin" "$T/.local/bin"
printf '#!/usr/bin/env bash\necho "opencode v2.4.1"\n' > "$T/.opencode/bin/opencode"
printf '#!/usr/bin/env bash\necho "openusage version 0.26.3"\n' > "$T/.local/bin/openusage"
chmod +x "$T/.opencode/bin/opencode" "$T/.local/bin/openusage"

check_version() {
	local label=$1 script=$2 func=$3 expected=$4 actual
	actual=$(bash -c '
		source "$1"
		"$2"
	' _ "$script" "$func" 2>/dev/null)
	if [[ $actual == *"$expected"* ]]; then
		pass "$label: detected ($actual)"
	else
		fail "$label: not detected (got: ${actual:-nothing})"
	fi
}

check_version opencode "$ROOT/setup/development/opencode.sh" opencode_version "v2.4.1"
check_version openusage "$ROOT/setup/development/openusage.sh" openusage_version "0.26.3"

[[ $FAILURES -eq 0 ]] || exit 1
