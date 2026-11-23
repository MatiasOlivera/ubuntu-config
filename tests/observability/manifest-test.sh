#!/usr/bin/env bash
#
# manifest-test.sh — hermetic tests for per-app disk accounting.
# Uses fixture files and a stubbed package-query command only.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OBS_SRC="$ROOT/setup/helpers/observability.sh"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

if [[ ! -f $OBS_SRC ]] || ! grep -q '^obs_check_manifest()' "$OBS_SRC" 2>/dev/null; then
	printf 'FAIL: disk accounting helpers missing (red state)\n' >&2
	exit 1
fi
if [[ ! -f $ROOT/tests/observability/app-paths.tsv ]]; then
	printf 'FAIL: app-paths.tsv missing (red state)\n' >&2
	exit 1
fi

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/.local/bin" "$T/root"
export HOME="$T/home"

source "$OBS_SRC"

check_status() {
	local name=$1 expected=$2 actual=$3
	if [[ $actual -eq $expected ]]; then pass "$name: status $actual"; else fail "$name: expected $expected, got $actual"; fi
}

# Build a fixture manifest from a real step label so validation can check both
# label coverage and allowed path roots.
printf 'install_uv\t%s/.local/bin/uv %s/.local/bin/uvx\n' "$HOME" "$HOME" > "$T/good.tsv"
printf 'install_uv\t/\n' > "$T/bad-path.tsv"
printf 'install_missing_app\t%s/.local/bin/uv\n' "$HOME" > "$T/bad-label.tsv"

for f in good bad-path bad-label; do
	err="$T/$f.err"
	if [[ $f == good ]]; then expected=0; else expected=1; fi
	obs_check_manifest "$T/$f.tsv" >"$T/$f.out" 2>"$err"
	check_status "manifest $f" "$expected" $?
done
if grep -q 'not a step label' "$T/bad-label.err"; then pass "unknown label reported"; else fail "unknown label not reported"; fi
if grep -q 'path outside allowed roots' "$T/bad-path.err"; then pass "unsafe path reported"; else fail "unsafe path not reported"; fi

# Known file sizes: 4096 + 8192 bytes across two declared paths.
head -c 4096 /dev/zero > "$HOME/.local/bin/uv"
head -c 8192 /dev/zero > "$HOME/.local/bin/uvx"
bytes=$(obs_disk_bytes install_uv "$T/good.tsv")
if [[ $bytes -ge 12288 ]]; then pass "disk bytes sum declared paths ($bytes)"; else fail "disk bytes too small: $bytes"; fi
if [[ ${OBS_DISK_BASIS:-} == approximate ]]; then pass "disk bytes marked approximate"; else fail "disk basis missing"; fi

# Package delta from a stubbed dpkg-query: one new package of 2048 KiB.
cat > "$T/dpkg-query" <<'EOF'
#!/usr/bin/env bash
printf 'git\t1234\n'
if [[ ${ADD_PKG:-0} == 1 ]]; then printf 'newpkg\t2048\n'; fi
EOF
chmod +x "$T/dpkg-query"
export OBS_E2E_DPKG_QUERY="$T/dpkg-query"

ADD_PKG=0 obs_pkg_snapshot "$T/before.pkgs"
ADD_PKG=1 obs_pkg_snapshot "$T/after.pkgs"
delta=$(obs_pkg_delta "$T/before.pkgs" "$T/after.pkgs")
if [[ $delta -eq 2048 ]]; then pass "apt package delta ($delta KiB)"; else fail "apt delta: expected 2048, got $delta"; fi
if [[ $(obs_pkg_delta "$T/before.pkgs" "$T/before.pkgs") -eq 0 ]]; then pass "no delta on unchanged set"; else fail "false delta on unchanged set"; fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all manifest checks passed\n'
