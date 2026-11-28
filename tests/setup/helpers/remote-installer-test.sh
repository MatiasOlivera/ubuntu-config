#!/usr/bin/env bash
# remote-installer-test.sh — hermetic tests for the shared remote installer runner.
# curl and the interpreter are stubs; TMPDIR is sandboxed. No network, no host changes.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${REMOTE_INSTALLER_SRC:-$ROOT/setup/helpers/remote-installer.sh}"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/tmp" "$T/stubs"
STUB_DIR="$T/stubs"
export STUB_DIR

cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/curl-calls"
out= prev=
for arg in "$@"; do
	[[ $prev == -o ]] && out=$arg
	prev=$arg
done
[[ ${CURL_FAIL:-0} != 1 ]] || exit 22
[[ -n $out ]] || exit 2
printf 'fixture installer script\n' > "$out"
EOF

cat > "$T/bin/installer" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/installer-calls"
cat "$1"
exit "${INSTALLER_RC:-0}"
EOF
chmod +x "$T/bin/"*

reset_case() {
	rm -f "$STUB_DIR/curl-calls" "$STUB_DIR/installer-calls"
}

run_install() {
	RC=0
	OUT="$(env PATH="$T/bin:$PATH" TMPDIR="$T/tmp" STUB_DIR="$STUB_DIR" \
		CURL_FAIL="${CURL_FAIL:-0}" INSTALLER_RC="${INSTALLER_RC:-0}" \
		bash -c 'source "$1" && remote_install "https://example.test/install.sh" installer --flag value' \
		bash "$SRC" 2>&1)" || RC=$?
}

# 1. A failed download never executes the installer and propagates curl's status.
reset_case
CURL_FAIL=1 INSTALLER_RC=0 run_install
if [[ $RC -eq 22 && ! -e $STUB_DIR/installer-calls ]] &&
	[[ -z $(find "$T/tmp" -mindepth 1 -print -quit) ]]; then
	pass 'failed download: no execution, status propagated, temp cleaned'
else
	fail "failed download (rc=$RC out=[$OUT])"
fi

# 2. A successful download is executed with the caller's flags.
reset_case
CURL_FAIL=0 INSTALLER_RC=0 run_install
if [[ $RC -eq 0 ]] && grep -Fxq 'fixture installer script' <<<"$OUT" &&
	grep -q -- '--flag value' "$STUB_DIR/installer-calls" &&
	[[ -z $(find "$T/tmp" -mindepth 1 -print -quit) ]]; then
	pass 'successful download: installer runs with flags, temp cleaned'
else
	fail "successful download (rc=$RC out=[$OUT])"
fi

# 3. Installer failure propagates to the step.
reset_case
CURL_FAIL=0 INSTALLER_RC=7 run_install
if [[ $RC -eq 7 ]]; then
	pass 'installer failure propagates'
else
	fail "installer failure (rc=$RC out=[$OUT])"
fi

# 4. Sourcing the helper has no side effects.
reset_case
env PATH="$T/bin:$PATH" TMPDIR="$T/tmp" STUB_DIR="$STUB_DIR" \
	bash -c 'source "$1"' bash "$SRC" >"$T/source.out" 2>&1
if [[ ! -s $T/source.out && ! -e $STUB_DIR/curl-calls ]]; then
	pass 'sourcing the helper writes nothing'
else
	fail "source-only (out=$(cat "$T/source.out"))"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all remote installer helper tests passed\n'
