#!/usr/bin/env bash
# Black-box, hermetic tests for OpenCode V2 installation (issue #48).
# Network is stubbed; files install only under a temporary HOME.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${OPENCODE_SRC:-$ROOT/setup/development/opencode.sh}"
FAILURES=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	printf 'ok: %s\n' "$1"
}

T="$(mktemp -d)" || { printf 'error: mktemp failed, refusing to run\n' >&2; exit 1; }
trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/bin" "$T/skip-bin" "$T/stubs" "$T/release" \
	"$T/payload" "$T/home" "$T/tmp"
export STUB_DIR="$T/stubs"
export STUB_RELEASE="$T/release"

# Only the two approved V2 source URLs are served. Any API or installer URL
# fails and is recorded, so a GitHub digest fallback cannot go unnoticed.
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
	https://raw.githubusercontent.com/anomalyco/homebrew-tap/master/opencode-v2.rb)
		[[ -f $STUB_DIR/fail-formula ]] && exit 22
		cp "$STUB_DIR/opencode-v2.rb" "$dest" || exit 22
		;;
	https://opencode.ai/files/bin/*/opencode-linux-x64-baseline.tar.gz|\
https://opencode.ai/files/bin/*/opencode-linux-arm64.tar.gz)
		[[ -f $STUB_DIR/fail-artifact ]] && exit 22
		asset=${url##*/}
		cp "$STUB_RELEASE/$asset" "$dest" || exit 22
		;;
	*) exit 22 ;;
esac
EOF
chmod +x "$T/bin/curl"

# Keep a failing opencode first on PATH for fresh-install cases.
cat > "$T/bin/opencode" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$T/bin/opencode"

cat > "$T/skip-bin/opencode" <<'EOF'
#!/usr/bin/env bash
printf 'OpenCode 2.3.2\n'
EOF
chmod +x "$T/skip-bin/opencode"

cat > "$T/bin/uname" <<'EOF'
#!/usr/bin/env bash
case $1 in
	-m) printf '%s\n' "${STUB_ARCH:-x86_64}" ;;
	-s) printf '%s\n' "${STUB_OS:-Linux}" ;;
	*) exec /usr/bin/uname "$@" ;;
esac
EOF
chmod +x "$T/bin/uname"

# Build small, deterministic archives with the same root entry as the formula.
fresh_release() {
	rm -rf -- "$T/release" "$T/payload" "$T/tmp" "$T/home/.opencode"
	rm -f -- "$T/stubs/curl-calls" "$T/stubs/fail-formula" \
		"$T/stubs/fail-artifact"
	mkdir -p "$T/release" "$T/payload" "$T/tmp"
	cat > "$T/payload/opencode" <<'EOF'
#!/usr/bin/env bash
printf 'OpenCode 2.3.2\n'
EOF
	chmod +x "$T/payload/opencode"
	tar -czf "$T/release/opencode-linux-x64-baseline.tar.gz" \
		-C "$T/payload" opencode
	tar -czf "$T/release/opencode-linux-arm64.tar.gz" \
		-C "$T/payload" opencode
	local x64 arm64
	x64="$(sha256sum "$T/release/opencode-linux-x64-baseline.tar.gz" | cut -d ' ' -f 1)"
	arm64="$(sha256sum "$T/release/opencode-linux-arm64.tar.gz" | cut -d ' ' -f 1)"
	cat > "$T/stubs/opencode-v2.rb" <<EOF
class OpencodeV2 < Formula
  version "2.3.2"
  on_linux do
    if Hardware::CPU.arm?
      url "https://opencode.ai/files/bin/2.3.2/opencode-linux-arm64.tar.gz"

      sha256 "$arm64"
    else
      url "https://opencode.ai/files/bin/2.3.2/opencode-linux-x64-baseline.tar.gz"

      sha256 "$x64"
    end
  end
end
EOF
}

refresh_x64_checksum() {
	local old new
	old="$(sed -n '/opencode-linux-x64-baseline.tar.gz/{n;n;s/.*sha256 "\([^"]*\)".*/\1/p;}' \
		"$T/stubs/opencode-v2.rb")"
	new="$(sha256sum "$T/release/opencode-linux-x64-baseline.tar.gz" | cut -d ' ' -f 1)"
	sed -i "s/$old/$new/" "$T/stubs/opencode-v2.rb"
}

# Invoke through the same standalone dispatcher contract as install.sh.
# Sets OUT, ERR and RC. Extra PATH directories are supplied in $1.
call() {
	local extrapath=${1:-}
	OUT="$(env PATH="$extrapath$T/bin:/usr/bin:/bin" HOME="$T/home" \
		TMPDIR="$T/tmp" STUB_DIR="$STUB_DIR" \
		STUB_RELEASE="$STUB_RELEASE" STUB_ARCH="${STUB_ARCH:-x86_64}" \
		STUB_OS="${STUB_OS:-Linux}" bash "$SRC" install 2>"$T/stderr")"
	RC=$?
	ERR="$(cat "$T/stderr")"
}

# 1. A working existing installation skips before the first network request.
fresh_release
call "$T/skip-bin:"
if [[ $RC -eq 0 && $OUT == *"skip: opencode already installed"* &&
	! -s "$T/stubs/curl-calls" ]]; then
	pass "skip guard reports skip and makes no network request"
else
	fail "skip guard (rc=$RC out=[$OUT] calls=[$(cat "$T/stubs/curl-calls" 2>/dev/null)])"
fi

# 2. x64 selects and verifies the formula's baseline artifact.
fresh_release
STUB_ARCH=x86_64 call
if [[ $RC -eq 0 && -x "$T/home/.opencode/bin/opencode" &&
	"$("$T/home/.opencode/bin/opencode" --version)" == "OpenCode 2.3.2" &&
	$OUT == *"installed: opencode OpenCode 2.3.2"* ]]; then
	pass "verified V2 x64-baseline artifact installs under HOME"
else
	fail "x64 install (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 3. Exactly two requests: the V2 formula and the selected x64 artifact.
if [[ "$(wc -l < "$T/stubs/curl-calls" 2>/dev/null)" -eq 2 ]] &&
	grep -Fxq 'https://raw.githubusercontent.com/anomalyco/homebrew-tap/master/opencode-v2.rb' "$T/stubs/curl-calls" &&
	grep -Fxq 'https://opencode.ai/files/bin/2.3.2/opencode-linux-x64-baseline.tar.gz' "$T/stubs/curl-calls" &&
	! grep -Eq 'api\.github\.com|/install$' "$T/stubs/curl-calls"; then
	pass "uses only the V2 formula and selected artifact; no digest fallback"
else
	fail "download discipline (calls=[$(cat "$T/stubs/curl-calls" 2>/dev/null)])"
fi

# 4. arm64 maps to the matching URL and checksum from the same formula.
fresh_release
STUB_ARCH=aarch64 call
if [[ $RC -eq 0 && -x "$T/home/.opencode/bin/opencode" &&
	"$("$T/home/.opencode/bin/opencode" --version)" == "OpenCode 2.3.2" &&
	$(tail -n 1 "$T/stubs/curl-calls") == \
	'https://opencode.ai/files/bin/2.3.2/opencode-linux-arm64.tar.gz' ]]; then
	pass "verified V2 arm64 artifact installs"
else
	fail "arm64 install (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 5. Tampered bytes fail verification before anything is installed.
fresh_release
printf 'tampered bytes\n' > "$T/release/opencode-linux-x64-baseline.tar.gz"
call
if [[ $RC -ne 0 && $ERR == *"checksum mismatch"* &&
	! -e "$T/home/.opencode/bin/opencode" ]]; then
	pass "tampered V2 archive rejected before installation"
else
	fail "tampered artifact (rc=$RC err=[$ERR])"
fi

# 6. Missing or malformed formula checksum fails without trying GitHub.
fresh_release
sed -i '/opencode-linux-x64-baseline.tar.gz/{n;n;d;}' \
	"$T/stubs/opencode-v2.rb"
call
if [[ $RC -ne 0 && $ERR == *"malformed V2 formula"* &&
	! -e "$T/home/.opencode/bin/opencode" &&
	"$(wc -l < "$T/stubs/curl-calls")" -eq 1 ]]; then
	pass "missing formula checksum fails closed without fallback"
else
	fail "missing formula checksum (rc=$RC err=[$ERR])"
fi

fresh_release
sed -i '/opencode-linux-x64-baseline.tar.gz/{n;n;s/sha256 ".*"/sha256 "not-a-digest"/;}' \
	"$T/stubs/opencode-v2.rb"
call
if [[ $RC -ne 0 && $ERR == *"malformed V2 formula"* &&
	! -e "$T/home/.opencode/bin/opencode" &&
	"$(wc -l < "$T/stubs/curl-calls")" -eq 1 ]]; then
	pass "malformed formula checksum fails closed without fallback"
else
	fail "malformed formula checksum (rc=$RC err=[$ERR] calls=[$(cat "$T/stubs/curl-calls" 2>/dev/null)])"
fi

# 7. Wrong hosts or mismatched archive names are not accepted as formula data.
fresh_release
sed -i 's#https://opencode.ai/files/bin/2.3.2/opencode-linux-x64-baseline.tar.gz#https://example.invalid/opencode-linux-x64-baseline.tar.gz#' \
	"$T/stubs/opencode-v2.rb"
call
if [[ $RC -ne 0 && $ERR == *"malformed V2 formula"* &&
	! -e "$T/home/.opencode/bin/opencode" &&
	"$(wc -l < "$T/stubs/curl-calls")" -eq 1 ]]; then
	pass "unapproved formula URL rejected"
else
	fail "unapproved formula URL (rc=$RC err=[$ERR])"
fi

# A V1 formula entry must not satisfy the OpenCode V2 installation contract.
fresh_release
sed -i 's/2\.3\.2/1.19.6/g' "$T/stubs/opencode-v2.rb"
call
if [[ $RC -ne 0 && $ERR == *"malformed V2 formula"* &&
	! -e "$T/home/.opencode/bin/opencode" &&
	"$(wc -l < "$T/stubs/curl-calls")" -eq 1 ]]; then
	pass "V1 formula entry rejected without artifact download"
else
	fail "V1 formula entry (rc=$RC out=[$OUT] err=[$ERR] calls=[$(cat "$T/stubs/curl-calls" 2>/dev/null)])"
fi

# 8. Formula and artifact transport errors fail closed.
fresh_release
touch "$T/stubs/fail-formula"
call
if [[ $RC -ne 0 && $ERR == *"cannot download V2 formula"* &&
	! -e "$T/home/.opencode/bin/opencode" ]]; then
	pass "formula download failure installs nothing"
else
	fail "formula download failure (rc=$RC err=[$ERR])"
fi

fresh_release
touch "$T/stubs/fail-artifact"
call
if [[ $RC -ne 0 && $ERR == *"cannot download"* &&
	! -e "$T/home/.opencode/bin/opencode" ]]; then
	pass "artifact download failure installs nothing"
else
	fail "artifact download failure (rc=$RC err=[$ERR])"
fi

# 9. An archive with a valid checksum but invalid tar data is rejected.
fresh_release
printf 'not a tar archive\n' > "$T/release/opencode-linux-x64-baseline.tar.gz"
refresh_x64_checksum
call
if [[ $RC -ne 0 && $ERR == *"cannot extract opencode"* &&
	! -e "$T/home/.opencode/bin/opencode" ]]; then
	pass "invalid archive rejected after checksum verification"
else
	fail "invalid archive (rc=$RC err=[$ERR])"
fi

# 10. A valid tarball without the expected binary is rejected.
fresh_release
printf 'unexpected file\n' > "$T/payload/unexpected"
tar -czf "$T/release/opencode-linux-x64-baseline.tar.gz" \
	-C "$T/payload" unexpected
refresh_x64_checksum
call
if [[ $RC -ne 0 && $ERR == *"cannot extract opencode"* &&
	! -e "$T/home/.opencode/bin/opencode" ]]; then
	pass "archive missing opencode rejected"
else
	fail "missing binary archive (rc=$RC err=[$ERR])"
fi

# 11. Unsupported architecture stops before downloading the formula.
fresh_release
STUB_ARCH=riscv64 call
if [[ $RC -ne 0 && $ERR == *"unsupported architecture: riscv64"* &&
	! -s "$T/stubs/curl-calls" &&
	! -e "$T/home/.opencode/bin/opencode" ]]; then
	pass "unsupported architecture fails before network"
else
	fail "unsupported architecture (rc=$RC err=[$ERR])"
fi

if [[ $FAILURES -ne 0 ]]; then
	printf 'FAIL: %s OpenCode test(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'ok: all OpenCode installer tests passed\n'
