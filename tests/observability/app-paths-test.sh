#!/usr/bin/env bash
# app-paths-test.sh — regression for declared install paths (issue #168).
# The drift check lives here; disk-byte reporting and the manifest are untouched.
# Stub filesystem only: no installs, no network, no du or dpkg-query.
# shellcheck disable=SC2016 # declared $HOME paths are literal fixture text

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$ROOT/tests/observability/app-paths.tsv"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

if [[ ! -f $MANIFEST ]]; then
	printf 'FAIL: app-paths.tsv missing (red state)\n' >&2
	exit 1
fi

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

# Map a declared path into a stub state: $HOME under <root>/home, absolute
# paths under <root>/root. Pure bash, no path-resolution commands.
stub_path() {
	local root=$1 path=$2
	case $path in
	\$HOME/*) printf '%s/home/%s\n' "$root" "${path#\$HOME/}" ;;
	/*) printf '%s/root/%s\n' "$root" "${path#/}" ;;
	*) return 1 ;;
	esac
}

# Fail when any declared path does not resolve under the stub root.
check_declared_paths() {
	local root=$1 manifest=$2 label paths path stub rc=0
	while IFS=$'\t' read -r label paths; do
		[[ -z $label || $label == \#* ]] && continue
		for path in $paths; do
			if ! stub=$(stub_path "$root" "$path"); then
				printf 'unmapped declared path: %s\n' "$path" >&2
				rc=1
				continue
			fi
			if [[ ! -e $stub ]]; then
				printf 'missing declared path for %s: %s\n' "$label" "$path" >&2
				rc=1
			fi
		done
	done < "$manifest"
	return $rc
}

# Populate a stub state with every declared path of a manifest.
build_stubs() {
	local root=$1 manifest=$2 label paths path stub
	while IFS=$'\t' read -r label paths; do
		[[ -z $label || $label == \#* ]] && continue
		for path in $paths; do
			stub=$(stub_path "$root" "$path") || continue
			mkdir -p "${stub%/*}" && : > "$stub"
		done
	done < "$manifest"
}

# Every declared path in the shipped manifest resolves in the stub state.
build_stubs "$T/state" "$MANIFEST"
if out=$(check_declared_paths "$T/state" "$MANIFEST" 2>&1); then
	pass "shipped manifest: all declared paths resolve"
else
	fail "shipped manifest: $out"
fi

# A declared path missing after a step must fail the check and name the path.
printf 'install_uv\t$HOME/.local/bin/uv $HOME/.local/bin/uvx\n' > "$T/fixture.tsv"
build_stubs "$T/fixture-state" "$T/fixture.tsv"
rm -f "$T/fixture-state/home/.local/bin/uvx"
if out=$(check_declared_paths "$T/fixture-state" "$T/fixture.tsv" 2>&1); then
	fail "missing declared path was not reported"
else
	pass "missing declared path fails the check"
fi
if [[ $out == *'missing declared path for install_uv: $HOME/.local/bin/uvx'* ]]; then
	pass "diagnostic names label and missing path"
else
	fail "missing path diagnostic: $out"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all app-paths checks passed\n'
