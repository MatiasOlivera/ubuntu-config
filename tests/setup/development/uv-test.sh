#!/usr/bin/env bash
#
# uv-test.sh — use-case tests for the uv installer (issue #50).
# Black-box: only exit codes, stdout/stderr markers and filesystem state are
# asserted, never helper names. Hermetic: stubbed curl/uname, fixture release
# (metadata, real SHA-256 checksums, tarballs with uv and uvx) built at test
# time, sandboxed HOME/TMPDIR and install dir. No real network, sudo or system
# directories are touched. UV_SRC overrides the script under test.
# Fail-closed: any failure exits 1.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${UV_SRC:-$ROOT/setup/development/uv.sh}"
FAILURES=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	printf 'ok: %s\n' "$1"
}

T="$(mktemp -d)" || { printf 'error: mktemp failed, refusing to run\n' >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/skip-bin" "$T/arch-bin" "$T/stubs" "$T/release" \
	"$T/home" "$T/tmp"
export STUB_DIR="$T/stubs" STUB_RELEASE="$T/release"

# Stub curl: logs every URL, answers only the fixture release endpoints and the
# legacy installer path, exits 22 otherwise. Marker files force per-endpoint
# failures.
cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
dest="" prev="" url=""
for a in "$@"; do
	[[ $prev == "-o" ]] && dest=$a
	case $a in *://*) url=$a ;; esac
	prev=$a
done
[[ -n $dest ]] || exit 22
printf '%s\n' "$url" >> "$STUB_DIR/curl-calls"
case $url in
	*api.github.com*/releases/latest)
		[[ -f $STUB_DIR/fail-latest ]] && exit 22
		cp "$STUB_RELEASE/release.json" "$dest" ;;
	*/releases/download/*/*.sha256)
		[[ -f $STUB_DIR/fail-sums ]] && exit 22
		asset=${url##*/}
		asset=${asset%.sha256}
		[[ -f $STUB_RELEASE/$asset.sha256 ]] || exit 22
		cp "$STUB_RELEASE/$asset.sha256" "$dest" ;;
	*/releases/download/*)
		[[ -f $STUB_DIR/fail-asset ]] && exit 22
		asset=${url##*/}
		[[ -f $STUB_RELEASE/$asset ]] || exit 22
		cp "$STUB_RELEASE/$asset" "$dest" ;;
	*/astral.sh/uv/install.sh)
		printf '#!/usr/bin/env bash\nprintf "legacy-installer\\n"\n' > "$dest" ;;
	*) exit 22 ;;
esac
EOF
chmod +x "$T/bin/curl"

# A failing `uv` on PATH so fresh-install cases cannot satisfy the skip guard
# via a host installation; the skip case shadows it via skip-bin.
cat > "$T/bin/uv" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$T/bin/uv"
cat > "$T/skip-bin/uv" <<'EOF'
#!/usr/bin/env bash
printf 'fake-uv 0.13.9\n'
EOF
chmod +x "$T/skip-bin/uv"

# Stub uname for the unsupported-architecture case.
cat > "$T/arch-bin/uname" <<'EOF'
#!/usr/bin/env bash
case $1 in
	-m) printf 'riscv64\n' ;;
	-s) printf 'Linux\n' ;;
	*) exec /usr/bin/uname "$@" ;;
esac
EOF
chmod +x "$T/arch-bin/uname"

# Fixture release: metadata listing both Linux assets, tarballs with the real
# upstream layout (uv-<target>/{uv,uvx}) and genuine sha256sum files.
fresh_release() {
	rm -rf "$T/release" "$T/payload" "$T/home/.local" "$T/tmp"
	mkdir -p "$T/release" "$T/payload" "$T/home" "$T/tmp"
	rm -f "$T/stubs/curl-calls" "$T/stubs/fail-latest" \
		"$T/stubs/fail-sums" "$T/stubs/fail-asset"
	cat > "$T/release/release.json" <<'EOF'
{
  "tag_name": "0.13.9",
  "assets": [
    {"name": "uv-x86_64-unknown-linux-gnu.tar.gz"},
    {"name": "uv-aarch64-unknown-linux-gnu.tar.gz"}
  ]
}
EOF
	local target payload asset
	for target in x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu; do
		payload="$T/payload/uv-$target"
		mkdir -p "$payload"
		printf '#!/usr/bin/env bash\nprintf "fake-uv 0.13.9\\n"\n' > "$payload/uv"
		printf '#!/usr/bin/env bash\nprintf "fake-uvx 0.13.9\\n"\n' > "$payload/uvx"
		chmod +x "$payload/uv" "$payload/uvx"
		asset="uv-$target.tar.gz"
		tar -czf "$T/release/$asset" -C "$T/payload" "uv-$target"
		(cd "$T/release" && sha256sum "$asset" > "$asset.sha256")
	done
}

# Call the installer exactly like setup/install.sh sources+dispatches it.
# Sets OUT, ERR, RC. Extra PATH dirs arrive as $1 (colon list).
call() {
	local extrapath=${1:-}
	OUT="$(env PATH="$extrapath$T/bin:/usr/bin:/bin" HOME="$T/home" \
		TMPDIR="$T/tmp" STUB_DIR="$STUB_DIR" STUB_RELEASE="$STUB_RELEASE" \
		bash "$SRC" install 2>"$T/stderr")"
	RC=$?
	ERR="$(cat "$T/stderr")"
}

no_install() {
	[[ ! -e $T/home/.local/bin/uv && ! -e $T/home/.local/bin/uvx ]]
}

# 1. Skip guard: an installed uv short-circuits before any network.
fresh_release
call "$T/skip-bin:"
if [[ $RC -eq 0 && $OUT == *"skip: uv already installed"* &&
	! -s "$T/stubs/curl-calls" ]]; then
	pass "skip guard reports skip and touches no network"
else
	fail "skip guard (rc=$RC out=[$OUT] calls=[$(cat "$T/stubs/curl-calls" 2>/dev/null)])"
fi

# 2. Happy path: the verified release installs uv and uvx into ~/.local/bin.
fresh_release
call
if [[ $RC -eq 0 && -x "$T/home/.local/bin/uv" &&
	-x "$T/home/.local/bin/uvx" &&
	"$("$T/home/.local/bin/uv" --version)" == "fake-uv 0.13.9" &&
	$OUT == *"installed: uv fake-uv 0.13.9"* ]]; then
	pass "verified release installs uv and uvx to ~/.local/bin"
else
	fail "verified install (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 2b. Exactly three downloads: release metadata, checksum, asset.
if [[ "$(wc -l < "$T/stubs/curl-calls" 2>/dev/null)" -eq 3 ]] &&
	! grep -vqE '(api\.github\.com/repos/astral-sh/uv/releases/latest|uv-(x86_64|aarch64)-unknown-linux-gnu\.tar\.gz(\.sha256)?)$' \
		"$T/stubs/curl-calls"; then
	pass "install fetches only metadata, checksum and release asset"
else
	fail "download discipline (calls=[$(cat "$T/stubs/curl-calls" 2>/dev/null)])"
fi

# 3. Tampered artifact: bytes differ from the publisher checksum, fail closed.
fresh_release
printf 'evil-bytes\n' > "$T/release/uv-x86_64-unknown-linux-gnu.tar.gz"
call
if [[ $RC -ne 0 && $ERR == *"checksum mismatch"* ]] && no_install; then
	pass "tampered tarball rejected, nothing installed"
else
	fail "tampered tarball (rc=$RC err=[$ERR])"
fi

# 4. Missing checksum material: publisher omits <asset>.sha256.
fresh_release
rm -f "$T/release/uv-x86_64-unknown-linux-gnu.tar.gz.sha256"
call
if [[ $RC -ne 0 && $ERR == *"cannot download checksum"* ]] && no_install; then
	pass "absent checksum rejected"
else
	fail "absent checksum (rc=$RC err=[$ERR])"
fi

# 5. Interrupted metadata download: the step must fail closed.
fresh_release
touch "$T/stubs/fail-latest"
call
if [[ $RC -ne 0 && $ERR == *"cannot download release metadata"* ]] && no_install; then
	pass "failed metadata download aborts with no install"
else
	fail "failed metadata download (rc=$RC err=[$ERR])"
fi

# 6. Interrupted asset download: the step must fail closed.
fresh_release
touch "$T/stubs/fail-asset"
call
if [[ $RC -ne 0 && $ERR == *"cannot download uv-x86_64-unknown-linux-gnu.tar.gz"* ]] && no_install; then
	pass "failed asset download aborts with no install"
else
	fail "failed asset download (rc=$RC err=[$ERR])"
fi

# 7. Checksum-valid but invalid archive.
fresh_release
printf 'evil-bytes\n' > "$T/release/uv-x86_64-unknown-linux-gnu.tar.gz"
(cd "$T/release" && sha256sum uv-x86_64-unknown-linux-gnu.tar.gz \
	> uv-x86_64-unknown-linux-gnu.tar.gz.sha256)
call
if [[ $RC -ne 0 && $ERR == *"not a valid tarball"* ]] && no_install; then
	pass "invalid archive rejected"
else
	fail "invalid archive (rc=$RC err=[$ERR])"
fi

# 8. Archive without the uv binary must not report success.
fresh_release
rm -rf "$T/payload" && mkdir -p "$T/payload/uv-x86_64-unknown-linux-gnu"
printf 'nope\n' > "$T/payload/uv-x86_64-unknown-linux-gnu/README"
tar -czf "$T/release/uv-x86_64-unknown-linux-gnu.tar.gz" \
	-C "$T/payload" uv-x86_64-unknown-linux-gnu
(cd "$T/release" && sha256sum uv-x86_64-unknown-linux-gnu.tar.gz \
	> uv-x86_64-unknown-linux-gnu.tar.gz.sha256)
call
if [[ $RC -ne 0 && $ERR == *"has no uv binary"* ]] && no_install; then
	pass "archive missing uv rejected"
else
	fail "archive missing uv (rc=$RC err=[$ERR])"
fi

# 9. Unsupported architecture: riscv64 host fails with a named error.
fresh_release
call "$T/arch-bin:"
if [[ $RC -ne 0 && $ERR == *"unsupported architecture: riscv64"* ]] && no_install; then
	pass "unsupported architecture named in error"
else
	fail "unsupported architecture (rc=$RC err=[$ERR])"
fi

# 10. Parent-run containment: sourced install_uv returns to its caller, leaves
# the caller's EXIT trap intact, and a failed install installs nothing.
fresh_release
printf 'evil-bytes\n' > "$T/release/uv-x86_64-unknown-linux-gnu.tar.gz"
cat > "$T/parent-run.sh" <<'EOF'
#!/usr/bin/env bash
source "$1"
trap 'printf "EXIT_TRAP\n"' EXIT
install_uv
rc=$?
printf 'SENTINEL rc=%s\n' "$rc"
exit "$rc"
EOF
PARENT="$(env PATH="$T/bin:/usr/bin:/bin" HOME="$T/home" TMPDIR="$T/tmp" \
	STUB_DIR="$STUB_DIR" STUB_RELEASE="$STUB_RELEASE" \
	bash "$T/parent-run.sh" "$SRC" 2>/dev/null)"
PRC=$?
if [[ $PRC -eq 1 && $PARENT == *"SENTINEL rc=1"* && $PARENT == *"EXIT_TRAP"* ]] && no_install; then
	pass "failed install returns to caller with caller trap intact"
else
	fail "parent-run containment (rc=$PRC out=[$PARENT])"
fi

if (( FAILURES )); then
	printf '%d failure(s)\n' "$FAILURES" >&2
	exit 1
fi
printf 'all tests passed\n'
