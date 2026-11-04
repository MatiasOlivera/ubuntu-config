#!/usr/bin/env bash
#
# copilot-test.sh — use-case tests for the Copilot CLI installer (issue #6).
# Black-box: only exit codes, stdout/stderr markers and filesystem state are
# asserted, never helper names. Hermetic: stubbed curl/uname, fixture release
# (tarball + genuine SHA256SUMS.txt) built at test time, sandboxed HOME,
# TMPDIR and PREFIX. No real network, sudo or system directories are ever
# touched. COPILOT_SRC overrides the script under test. Fail-closed: any
# failure exits 1.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${COPILOT_SRC:-$ROOT/setup/development/copilot.sh}"
FAILURES=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	printf 'ok: %s\n' "$1"
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/skip-bin" "$T/arch-bin" "$T/stubs" "$T/release" \
	"$T/payload" "$T/prefix" "$T/home" "$T/tmp"
export STUB_DIR="$T/stubs"
export STUB_RELEASE="$T/release"

# Stub curl: logs every URL, serves only the fixture release endpoints
# (SHA256SUMS.txt and releases/latest/download/<asset>), exits 22 otherwise
# — the same curl failure code. Marker files force per-endpoint failures.
cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
dest="" prev="" url=""
for a in "$@"; do
	[[ $prev == "-o" ]] && dest=$a
	case $a in *://*) url=$a ;; esac
	prev=$a
done
printf '%s\n' "$url" >> "$STUB_DIR/curl-calls"
case $url in
	*/SHA256SUMS.txt)
		[[ -f $STUB_DIR/fail-sums ]] && exit 22
		cp "$STUB_RELEASE/SHA256SUMS.txt" "$dest" ;;
	*/releases/latest/download/*)
		[[ -f $STUB_DIR/fail-asset ]] && exit 22
		asset=${url##*/}
		[[ -f $STUB_RELEASE/$asset ]] || exit 22
		cp "$STUB_RELEASE/$asset" "$dest" ;;
	*) exit 22 ;;
esac
EOF
chmod +x "$T/bin/curl"

# Stub copilot (skip guard) and stub uname (unsupported architecture).
cat > "$T/skip-bin/copilot" <<'EOF'
#!/usr/bin/env bash
printf 'fake-copilot 9.9.9\n'
EOF
chmod +x "$T/skip-bin/copilot"
cat > "$T/arch-bin/uname" <<'EOF'
#!/usr/bin/env bash
case $1 in
	-m) printf 'riscv64\n' ;;
	-s) printf 'Linux\n' ;;
	*) exec /usr/bin/uname "$@" ;;
esac
EOF
chmod +x "$T/arch-bin/uname"

# Fixture release: tarball with a stub `copilot` binary at its root (real
# upstream layout), published under both linux arch names, checksums
# generated with the real sha256sum so the format is genuine.
fresh_release() {
	rm -rf "$T/release" "$T/payload" "$T/prefix" "$T/tmp"
	mkdir -p "$T/release" "$T/payload" "$T/prefix" "$T/tmp"
	rm -f "$T/stubs/curl-calls" "$T/stubs/fail-sums" "$T/stubs/fail-asset"
	cat > "$T/payload/copilot" <<'EOF'
#!/usr/bin/env bash
printf 'fake-copilot 9.9.9\n'
EOF
	chmod +x "$T/payload/copilot"
	tar -czf "$T/release/copilot-linux-x64.tar.gz" -C "$T/payload" copilot
	tar -czf "$T/release/copilot-linux-arm64.tar.gz" -C "$T/payload" copilot
	(cd "$T/release" &&
		sha256sum copilot-linux-x64.tar.gz copilot-linux-arm64.tar.gz \
		> SHA256SUMS.txt)
}

# Call the installer exactly like setup/install.sh sources+dispatches it,
# with a PATH that exposes only the stubs (plus coreutils).
# Sets OUT, ERR, RC. Extra PATH dirs arrive as $1 (colon list).
call() {
	local extrapath=${1:-}
	OUT="$(env PATH="$extrapath$T/bin:/usr/bin:/bin" HOME="$T/home" \
		TMPDIR="$T/tmp" PREFIX="$T/prefix" STUB_DIR="$STUB_DIR" \
		STUB_RELEASE="$STUB_RELEASE" \
		bash "$SRC" install 2>"$T/stderr")"
	RC=$?
	ERR="$(cat "$T/stderr")"
}

# 1. Skip guard: already-installed copilot short-circuits before any network.
fresh_release
PATH_SAVE="$T/skip-bin:"
call "$PATH_SAVE"
if [[ $RC -eq 0 && $OUT == *"skip: copilot already installed"* &&
	! -s "$T/stubs/curl-calls" ]]; then
	pass "skip guard reports skip and touches no network"
else
	fail "skip guard (rc=$RC out=[$OUT] calls=[$(cat "$T/stubs/curl-calls" 2>/dev/null)])"
fi

# 2. Happy path: fresh PREFIX installs the verified binary.
fresh_release
call
if [[ $RC -eq 0 && -x "$T/prefix/bin/copilot" &&
	"$("$T/prefix/bin/copilot" --version)" == "fake-copilot 9.9.9" &&
	$OUT == *"installed: copilot fake-copilot 9.9.9"* ]]; then
	pass "verified release installs to PREFIX/bin"
else
	fail "verified install (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 2b. Exactly two downloads: checksums, then the asset — no other URL.
if [[ "$(wc -l < "$T/stubs/curl-calls" 2>/dev/null)" -eq 2 ]] &&
	! grep -vqE '/(SHA256SUMS\.txt|copilot-(linux-x64|linux-arm64)\.tar\.gz)$' \
		"$T/stubs/curl-calls"; then
	pass "install fetches only checksums and the release asset"
else
	fail "download discipline (calls=[$(cat "$T/stubs/curl-calls" 2>/dev/null)])"
fi

# 3. Tampered artifact: bytes differ from the published checksum, fail closed.
fresh_release
printf 'evil-bytes\n' | tee "$T/release/copilot-linux-x64.tar.gz" \
	"$T/release/copilot-linux-arm64.tar.gz" > /dev/null
call
if [[ $RC -ne 0 && $ERR == *"checksum mismatch"* &&
	! -e "$T/prefix/bin/copilot" ]]; then
	pass "tampered tarball rejected, nothing installed"
else
	fail "tampered tarball (rc=$RC err=[$ERR])"
fi

# 4. Missing checksum line: publisher omits our asset from SHA256SUMS.txt.
fresh_release
( cd "$T/release" && sha256sum copilot-linux-x64.tar.gz |
	sed 's/ copilot-linux-x64\.tar\.gz/ copilot-win32-x64.zip/' > SHA256SUMS.txt )
call
if [[ $RC -ne 0 && $ERR == *"no checksum published"* &&
	! -e "$T/prefix/bin/copilot" ]]; then
	pass "absent checksum line rejected"
else
	fail "absent checksum line (rc=$RC err=[$ERR])"
fi

# 5. Interrupted asset download: curl fails, the installer must fail closed.
fresh_release
touch "$T/stubs/fail-asset"
call
if [[ $RC -ne 0 && $ERR == *"cannot download"* &&
	! -e "$T/prefix/bin/copilot" ]]; then
	pass "failed asset download aborts with no install"
else
	fail "failed asset download (rc=$RC err=[$ERR])"
fi

# 6. Unsupported architecture: riscv64 host fails with a named error.
fresh_release
call "$T/arch-bin:"
if [[ $RC -ne 0 && $ERR == *"unsupported architecture"* ]]; then
	pass "unsupported architecture named in error"
else
	fail "unsupported architecture (rc=$RC err=[$ERR])"
fi

if (( FAILURES )); then
	printf '%d failure(s)\n' "$FAILURES" >&2
	exit 1
fi
printf 'all tests passed\n'
