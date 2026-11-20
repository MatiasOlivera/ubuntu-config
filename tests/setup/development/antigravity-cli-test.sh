#!/usr/bin/env bash
# Hermetic behavior test for the Antigravity CLI installer.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${ANTIGRAVITY_CLI_SRC:-$ROOT/setup/development/antigravity-cli.sh}"
T="$(mktemp -d)" || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/stubs" "$T/payload" "$T/home" "$T/tmp"
export STUB_DIR="$T/stubs"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
url="" dest="" prev=""
for arg in "$@"; do
	[[ $prev == -o ]] && dest=$arg
	case $arg in
		*://*) url=$arg ;;
	esac
	prev=$arg
done
printf '%s\n' "$url" >> "$STUB_DIR/curl-calls"
case $url in
	*/manifests/linux_amd64.json)
		[[ -e $STUB_DIR/fail-manifest ]] && exit 22
		cp "$STUB_DIR/manifest.json" "$dest" ;;
		*/manifests/linux_arm64.json) cp "$STUB_DIR/manifest-arm64.json" "$dest" ;;
	*/cli_linux_x64.tar.gz)
		[[ -e $STUB_DIR/fail-google-asset ]] && exit 22
		cp "$STUB_DIR/cli_linux_x64.tar.gz" "$dest" ;;
		*/cli_linux_arm64.tar.gz) cp "$STUB_DIR/cli_linux_arm64.tar.gz" "$dest" ;;
	*/releases/tags/1.5.13)
		[[ -e $STUB_DIR/fail-github-api ]] && exit 22
		cp "$STUB_DIR/github-release.json" "$dest" ;;
		*/releases/download/1.5.13/agy_cli_linux_x64.tar.gz)
		[[ -e $STUB_DIR/fail-github-asset ]] && exit 22
			cp "$STUB_DIR/agy_cli_linux_x64.tar.gz" "$dest" ;;
		*/releases/download/1.5.13/agy_cli_linux_arm64.tar.gz)
			cp "$STUB_DIR/agy_cli_linux_arm64.tar.gz" "$dest" ;;
	*) exit 22 ;;
esac
EOF
cat > "$T/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/sudo-calls"
exit 0
EOF
cat > "$T/bin/agy" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$T/bin/curl" "$T/bin/sudo" "$T/bin/agy"

cat > "$T/payload/antigravity" <<'EOF'
#!/usr/bin/env bash
printf 'Antigravity CLI 1.5.13\n'
EOF
chmod +x "$T/payload/antigravity"
tar -czf "$T/stubs/cli_linux_x64.tar.gz" -C "$T/payload" antigravity
cp "$T/stubs/cli_linux_x64.tar.gz" "$T/stubs/cli_linux_arm64.tar.gz"
cp "$T/stubs/cli_linux_x64.tar.gz" "$T/stubs/agy_cli_linux_x64.tar.gz"
cp "$T/stubs/cli_linux_x64.tar.gz" "$T/stubs/agy_cli_linux_arm64.tar.gz"
sha512="$(sha512sum "$T/stubs/cli_linux_x64.tar.gz" | cut -d' ' -f1)"
printf '{"version":"1.5.13","url":"https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.13/linux-x64/cli_linux_x64.tar.gz","sha512":"%s"}\n' \
	"$sha512" > "$T/stubs/manifest.json"
printf '{"version":"1.5.13","url":"https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.13/linux-arm/cli_linux_arm64.tar.gz","sha512":"%s"}\n' \
	"$sha512" > "$T/stubs/manifest-arm64.json"
sha256="$(sha256sum "$T/stubs/agy_cli_linux_x64.tar.gz" | cut -d' ' -f1)"
printf '{"tag_name":"1.5.13","assets":[{"name":"agy_cli_linux_x64.tar.gz","digest":"sha256:%s","browser_download_url":"https://github.com/google-antigravity/antigravity-cli/releases/download/1.5.13/agy_cli_linux_x64.tar.gz"},{"name":"agy_cli_linux_arm64.tar.gz","digest":"sha256:%s","browser_download_url":"https://github.com/google-antigravity/antigravity-cli/releases/download/1.5.13/agy_cli_linux_arm64.tar.gz"}]}\n' \
	"$sha256" "$sha256" > "$T/stubs/github-release.json"

call() {
	local path_prefix=$1 home=$2
	OUT="$(env PATH="${path_prefix}$T/bin:/usr/bin:/bin" HOME="$home" \
		TMPDIR="$T/tmp" STUB_DIR="$STUB_DIR" \
		bash "$SRC" install 2>"$T/stderr")"
	RC=$?
	ERR="$(cat "$T/stderr")"
}

call "" "$T/home"
if [[ $RC -eq 0 && -x "$T/home/.local/bin/agy" &&
	"$("$T/home/.local/bin/agy" --version)" == "Antigravity CLI 1.5.13" &&
	$OUT == *"installed: antigravity-cli Antigravity CLI 1.5.13"* ]]; then
	printf 'ok: publisher-verified x64 artifact is installed as agy\n'
else
	fail "publisher-verified x64 install (rc=$RC out=[$OUT] err=[$ERR])"
fi
if [[ "$(wc -l < "$T/stubs/curl-calls")" -eq 2 ]] &&
	! grep -q 'install.sh' "$T/stubs/curl-calls" &&
	! grep -q 'api.github.com' "$T/stubs/curl-calls"; then
	printf 'ok: Google manifest and artifact are the only downloads\n'
else
	fail "download source order (calls=[$(cat "$T/stubs/curl-calls")])"
fi
if grep -qF "$T/home/.local/bin/agy /usr/local/bin/agy" "$T/stubs/sudo-calls"; then
	printf 'ok: existing public agy symlink is preserved\n'
else
	fail "public agy symlink invocation (calls=[$(cat "$T/stubs/sudo-calls" 2>/dev/null)])"
fi

# A mismatching publisher archive must not reach the install directory.
cp "$T/stubs/cli_linux_x64.tar.gz" "$T/stubs/cli_linux_x64.good"
printf 'tampered archive\n' > "$T/stubs/cli_linux_x64.tar.gz"
rm -f "$T/stubs/sudo-calls"
call "" "$T/tampered-home"
if [[ $RC -ne 0 && $ERR == *"sha512 mismatch"* &&
	! -e "$T/tampered-home/.local/bin/agy" && ! -e "$T/stubs/sudo-calls" ]]; then
	printf 'ok: tampered publisher artifact is rejected before installation\n'
else
	fail "tampered publisher artifact (rc=$RC err=[$ERR])"
fi
mv "$T/stubs/cli_linux_x64.good" "$T/stubs/cli_linux_x64.tar.gz"

# An interrupted publisher artifact download leaves no installed binary.
touch "$T/stubs/fail-google-asset"
rm -f "$T/stubs/curl-calls" "$T/stubs/sudo-calls"
call "" "$T/failed-download-home"
if [[ $RC -ne 0 && $ERR == *"cannot download cli_linux_x64.tar.gz"* &&
	! -e "$T/failed-download-home/.local/bin/agy" && ! -e "$T/stubs/sudo-calls" ]]; then
	printf 'ok: interrupted publisher artifact download installs nothing\n'
else
	fail "interrupted publisher artifact download (rc=$RC err=[$ERR])"
fi
rm -f "$T/stubs/fail-google-asset"

# A checksum field with malformed content is an error, not permission to
# downgrade to GitHub's digest.
cp "$T/stubs/manifest.json" "$T/stubs/manifest-good.json"
printf '{"version":"1.5.13","url":"https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.13/linux-x64/cli_linux_x64.tar.gz","sha512":"bad"}\n' \
	> "$T/stubs/manifest.json"
rm -f "$T/stubs/curl-calls"
call "" "$T/bad-sha512-home"
if [[ $RC -ne 0 && $ERR == *"malformed publisher manifest"* &&
	! -e "$T/bad-sha512-home/.local/bin/agy" &&
	$(wc -l < "$T/stubs/curl-calls") -eq 1 ]] &&
	! grep -q 'api.github.com' "$T/stubs/curl-calls"; then
	printf 'ok: malformed publisher digest does not trigger GitHub fallback\n'
else
	fail "malformed publisher digest (rc=$RC err=[$ERR])"
fi
mv "$T/stubs/manifest-good.json" "$T/stubs/manifest.json"

# ARM64 selects the publisher's arm64 manifest and installs its archive.
mkdir -p "$T/arm-bin"
cat > "$T/arm-bin/uname" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == -m ]]; then
	printf 'aarch64\n'
else
	exec /usr/bin/uname "$@"
fi
EOF
chmod +x "$T/arm-bin/uname"
rm -f "$T/stubs/curl-calls"
call "$T/arm-bin:" "$T/arm-home"
if [[ $RC -eq 0 && -x "$T/arm-home/.local/bin/agy" &&
	$(cat "$T/stubs/curl-calls") == *linux_arm64.json* ]]; then
	printf 'ok: ARM64 selects the matching publisher manifest and artifact\n'
else
	fail "ARM64 publisher install (rc=$RC out=[$OUT] err=[$ERR])"
fi

# A working version guard must skip before calling curl.
mkdir -p "$T/skip-bin"
cat > "$T/skip-bin/agy" <<'EOF'
#!/usr/bin/env bash
printf 'Antigravity CLI 1.5.13\n'
EOF
chmod +x "$T/skip-bin/agy"
rm -f "$T/stubs/curl-calls" "$T/stubs/sudo-calls"
call "$T/skip-bin:" "$T/skip-home"
if [[ $RC -eq 0 && $OUT == *"skip: antigravity already installed"* &&
	! -e "$T/stubs/curl-calls" && -e "$T/stubs/sudo-calls" ]]; then
	printf 'ok: installed CLI skips network and keeps the public symlink\n'
else
	fail "network-free skip guard (rc=$RC out=[$OUT] err=[$ERR])"
fi

# If Google provides a valid manifest but no checksum, use the exact GitHub
# release asset's SHA-256 digest for the same version.
cp "$T/stubs/manifest.json" "$T/stubs/manifest-with-sha512.json"
printf '{"version":"1.5.13","url":"https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.13/linux-x64/cli_linux_x64.tar.gz"}\n' \
	> "$T/stubs/manifest.json"
rm -f "$T/stubs/curl-calls" "$T/stubs/sudo-calls"
call "" "$T/github-fallback-home"
if [[ $RC -eq 0 && -x "$T/github-fallback-home/.local/bin/agy" &&
	$OUT == *"installed: antigravity-cli Antigravity CLI 1.5.13"* &&
	$(wc -l < "$T/stubs/curl-calls") -eq 3 ]] &&
	grep -q 'api.github.com/repos/google-antigravity/antigravity-cli/releases/tags/1.5.13' "$T/stubs/curl-calls" &&
	grep -q 'releases/download/1.5.13/agy_cli_linux_x64.tar.gz' "$T/stubs/curl-calls" &&
	! grep -q 'storage.googleapis.com' "$T/stubs/curl-calls"; then
	printf 'ok: GitHub digest is used only when Google publishes no checksum\n'
else
	fail "GitHub digest fallback (rc=$RC out=[$OUT] err=[$ERR] calls=[$(cat "$T/stubs/curl-calls" 2>/dev/null)])"
fi
mv "$T/stubs/manifest-with-sha512.json" "$T/stubs/manifest.json"

# The fallback selects the architecture-matched GitHub asset too.
cp "$T/stubs/manifest-arm64.json" "$T/stubs/manifest-arm64-with-sha512.json"
printf '{"version":"1.5.13","url":"https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.13/linux-arm/cli_linux_arm64.tar.gz"}\n' \
	> "$T/stubs/manifest-arm64.json"
rm -f "$T/stubs/curl-calls"
call "$T/arm-bin:" "$T/github-arm64-home"
if [[ $RC -eq 0 && -x "$T/github-arm64-home/.local/bin/agy" &&
	$OUT == *"installed: antigravity-cli Antigravity CLI 1.5.13"* ]] &&
	grep -q 'releases/download/1.5.13/agy_cli_linux_arm64.tar.gz' "$T/stubs/curl-calls"; then
	printf 'ok: GitHub fallback selects the matching ARM64 asset\n'
else
	fail "GitHub ARM64 fallback (rc=$RC out=[$OUT] err=[$ERR] calls=[$(cat "$T/stubs/curl-calls" 2>/dev/null)])"
fi
mv "$T/stubs/manifest-arm64-with-sha512.json" "$T/stubs/manifest-arm64.json"

# A missing GitHub digest is not a reason to install unverified bytes.
cp "$T/stubs/manifest.json" "$T/stubs/manifest-with-sha512.json"
cp "$T/stubs/github-release.json" "$T/stubs/github-release-with-digest.json"
printf '{"version":"1.5.13","url":"https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.13/linux-x64/cli_linux_x64.tar.gz"}\n' \
	> "$T/stubs/manifest.json"
printf '{"tag_name":"1.5.13","assets":[{"name":"agy_cli_linux_x64.tar.gz","digest":null,"browser_download_url":"https://github.com/google-antigravity/antigravity-cli/releases/download/1.5.13/agy_cli_linux_x64.tar.gz"}]}\n' \
	> "$T/stubs/github-release.json"
rm -f "$T/stubs/curl-calls" "$T/stubs/sudo-calls"
call "" "$T/no-digest-home"
if [[ $RC -ne 0 && $ERR == *"no published GitHub sha256"* &&
	! -e "$T/no-digest-home/.local/bin/agy" &&
	$(wc -l < "$T/stubs/curl-calls") -eq 2 ]] &&
	! grep -q 'releases/download' "$T/stubs/curl-calls"; then
	printf 'ok: missing integrity material fails closed without downloading an artifact\n'
else
	fail "missing integrity material (rc=$RC err=[$ERR] calls=[$(cat "$T/stubs/curl-calls" 2>/dev/null)])"
fi
mv "$T/stubs/manifest-with-sha512.json" "$T/stubs/manifest.json"
mv "$T/stubs/github-release-with-digest.json" "$T/stubs/github-release.json"

# A publisher network or parse failure must not trigger the weaker fallback.
touch "$T/stubs/fail-manifest"
rm -f "$T/stubs/curl-calls"
call "" "$T/manifest-network-home"
if [[ $RC -ne 0 && $ERR == *"cannot download publisher manifest"* &&
	! -e "$T/manifest-network-home/.local/bin/agy" &&
	$(wc -l < "$T/stubs/curl-calls") -eq 1 ]] &&
	! grep -q 'api.github.com' "$T/stubs/curl-calls"; then
	printf 'ok: publisher manifest transport failure stays fail-closed\n'
else
	fail "publisher manifest transport failure (rc=$RC err=[$ERR])"
fi
rm -f "$T/stubs/fail-manifest"
printf 'not-json\n' > "$T/stubs/manifest.json"
rm -f "$T/stubs/curl-calls"
call "" "$T/malformed-manifest-home"
if [[ $RC -ne 0 && $ERR == *"malformed publisher manifest"* &&
	! -e "$T/malformed-manifest-home/.local/bin/agy" &&
	$(wc -l < "$T/stubs/curl-calls") -eq 1 ]] &&
	! grep -q 'api.github.com' "$T/stubs/curl-calls"; then
	printf 'ok: malformed publisher manifest stays fail-closed\n'
else
	fail "malformed publisher manifest (rc=$RC err=[$ERR])"
fi
cp "$T/stubs/manifest-arm64.json" "$T/stubs/manifest.json"

# GitHub fallback downloads must also match the digest before installation.
printf '{"version":"1.5.13","url":"https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.13/linux-x64/cli_linux_x64.tar.gz"}\n' \
	> "$T/stubs/manifest.json"
cp "$T/stubs/agy_cli_linux_x64.tar.gz" "$T/stubs/agy_cli_linux_x64.good"
printf 'tampered fallback archive\n' > "$T/stubs/agy_cli_linux_x64.tar.gz"
rm -f "$T/stubs/curl-calls"
call "" "$T/tampered-fallback-home"
if [[ $RC -ne 0 && $ERR == *"sha256 mismatch"* &&
	! -e "$T/tampered-fallback-home/.local/bin/agy" ]]; then
	printf 'ok: tampered GitHub fallback artifact is rejected\n'
else
	fail "tampered GitHub fallback artifact (rc=$RC err=[$ERR])"
fi
mv "$T/stubs/agy_cli_linux_x64.good" "$T/stubs/agy_cli_linux_x64.tar.gz"
cp "$T/stubs/manifest-arm64.json" "$T/stubs/manifest.json"

# Unsupported architectures fail before the network is touched.
mkdir -p "$T/unsupported-bin"
cat > "$T/unsupported-bin/uname" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == -m ]]; then
	printf 'riscv64\n'
else
	exec /usr/bin/uname "$@"
fi
EOF
chmod +x "$T/unsupported-bin/uname"
rm -f "$T/stubs/curl-calls"
call "$T/unsupported-bin:" "$T/unsupported-home"
if [[ $RC -ne 0 && $ERR == *"unsupported architecture: riscv64"* &&
	! -e "$T/stubs/curl-calls" && ! -e "$T/unsupported-home/.local/bin/agy" ]]; then
	printf 'ok: unsupported architecture fails before network access\n'
else
	fail "unsupported architecture (rc=$RC err=[$ERR])"
fi
