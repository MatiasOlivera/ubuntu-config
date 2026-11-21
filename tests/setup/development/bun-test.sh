#!/usr/bin/env bash
#
# bun-test.sh — hermetic use-case tests for issue #8.
# Black-box: asserts status, output, downloads and files, never helper names.
# curl, sudo and uname are local stubs; fixtures use real ZIP/sha256sum; HOME,
# TMPDIR and the install prefix are sandboxed. No network or system changes.
# BUN_SRC can override the script under test. Fail-closed: any failure exits 1.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${BUN_SRC:-$ROOT/setup/development/bun.sh}"
FAILURES=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	printf 'ok: %s\n' "$1"
}

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/stubs" "$T/release" "$T/payload" "$T/home" "$T/tmp"
export STUB_DIR="$T/stubs" STUB_RELEASE="$T/release"

cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
dest="" prev="" url=""
for a in "$@"; do
	[[ $prev == -o ]] && dest=$a
	case $a in *://*) url=$a ;; esac
	prev=$a
done
[[ -n $dest ]] || exit 22
printf '%s\n' "$url" >> "$STUB_DIR/curl-calls"
case $url in
	*/repos/oven-sh/bun/releases/latest)
		[[ ! -f $STUB_DIR/fail-latest ]] || exit 22
		cp "$STUB_RELEASE/release.json" "$dest" ;;
	*/releases/download/*/SHASUMS256.txt)
		[[ ! -f $STUB_DIR/fail-sums ]] || exit 22
		[[ -f $STUB_RELEASE/SHASUMS256.txt ]] || exit 22
		cp "$STUB_RELEASE/SHASUMS256.txt" "$dest" ;;
	*/releases/download/*)
		[[ ! -f $STUB_DIR/fail-asset ]] || exit 22
		asset=${url##*/}
		[[ -f $STUB_RELEASE/$asset ]] || exit 22
		cp "$STUB_RELEASE/$asset" "$dest" ;;
	*) exit 22 ;;
esac
EOF

cat > "$T/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/sudo-calls"
[[ ! -f $STUB_DIR/fail-sudo ]] || exit 1
exit 0
EOF

cat > "$T/bin/uname" <<'EOF'
#!/usr/bin/env bash
[[ $1 == -m ]] || exit 2
printf '%s\n' "${BUN_TEST_ARCH:-x86_64}"
EOF
chmod +x "$T/bin/"*

# Real ZIP payload: bun's release archive contains only <asset>/bun.
make_artifact() {
	local asset=$1
	local entry=${asset%.zip}
	rm -rf "$T/payload/$entry"
	mkdir -p "$T/payload/$entry"
	printf '#!/usr/bin/env bash\nprintf "bun fixture 9.9.9\\n"\n' > "$T/payload/$entry/bun"
	chmod +x "$T/payload/$entry/bun"
	(cd "$T/payload" && zip -qr "$STUB_RELEASE/$asset" "$entry")
	# Publisher SHASUMS256.txt lists every asset; append so both archs stay.
	(cd "$STUB_RELEASE" && sha256sum "$asset" >> SHASUMS256.txt)
}

make_metadata() {
	local mode=${1:-good}
	python3 - "$STUB_RELEASE/release.json" "$STUB_RELEASE/SHASUMS256.txt" "$mode" <<'PY'
import json
import sys

out, sums_path, mode = sys.argv[1:]
with open(sums_path, encoding="utf-8") as handle:
    sums = handle.read().strip()
if mode == "bad-sums":
    sums = sums.replace(sums.split()[0], "f" * 64)
    with open(sums_path, "w", encoding="utf-8") as handle:
        handle.write(sums + "\n")
assets = [
    {"name": "decoy.zip", "browser_download_url": "https://github.com/oven-sh/bun/releases/download/bun-v9.9.9/decoy.zip"},
]
for name in ("bun-linux-x64.zip", "bun-linux-aarch64.zip"):
    assets.append({
        "name": name,
        "browser_download_url": f"https://github.com/oven-sh/bun/releases/download/bun-v9.9.9/{name}",
    })
if mode != "no-assets":
    assets.append({"name": "SHASUMS256.txt", "browser_download_url": "https://github.com/oven-sh/bun/releases/download/bun-v9.9.9/SHASUMS256.txt"})
with open(out, "w", encoding="utf-8") as handle:
    document = {"tag_name": "bun-v9.9.9", "assets": assets}
    if mode != "no-tag":
        document["tag_name"] = "bun-v9.9.9"
    else:
        document.pop("tag_name")
    json.dump(document, handle)
PY
}

fresh_release() {
	rm -rf "$T/release" "$T/payload" "$T/home/.bun" "$T/tmp"
	mkdir -p "$T/release" "$T/payload" "$T/home" "$T/tmp"
	rm -f "$STUB_DIR/curl-calls" "$STUB_DIR/sudo-calls" "$STUB_DIR/fail-latest" \
		"$STUB_DIR/fail-sums" "$STUB_DIR/fail-asset" "$STUB_DIR/fail-sudo"
	rm -f "$STUB_RELEASE/SHASUMS256.txt"
	make_artifact bun-linux-x64.zip
	make_artifact bun-linux-aarch64.zip
	make_metadata good
}

call() {
	OUT="$(env PATH="$T/bin:/usr/bin:/bin" HOME="$T/home" TMPDIR="$T/tmp" \
		STUB_DIR="$STUB_DIR" STUB_RELEASE="$STUB_RELEASE" \
		BUN_TEST_ARCH="${BUN_TEST_ARCH:-x86_64}" \
		bash "$SRC" install 2>"$T/stderr")"
	RC=$?
	ERR="$(cat "$T/stderr")"
}

binary() { printf '%s/.bun/bin/bun\n' "$T/home"; }
no_install() { [[ ! -e $(binary) ]]; }

# 1. Skip guard: installed bun short-circuits without network or sudo.
fresh_release
mkdir -p "$(dirname "$(binary)")"
printf '#!/usr/bin/env bash\nprintf "bun fixture 9.9.9\\n"\n' > "$(binary)"
chmod +x "$(binary)"
call
if [[ $RC -eq 0 && $OUT == *"skip: bun already installed"* &&
	! -s "$STUB_DIR/curl-calls" && ! -s "$STUB_DIR/sudo-calls" ]]; then
	pass "skip guard reports skip with no network or sudo"
else
	fail "skip guard (rc=$RC out=[$OUT])"
fi

# 2/3. Supported architectures install a runnable binary with the publisher zip.
for spec in "x86_64:bun-linux-x64.zip" "aarch64:bun-linux-aarch64.zip"; do
	arch=${spec%%:*}
	asset=${spec#*:}
	fresh_release
	BUN_TEST_ARCH=$arch
	call
	if [[ $RC -eq 0 && -x $(binary) && $OUT == *"installed: bun bun fixture 9.9.9"* &&
		"$($(binary) --version)" == "bun fixture 9.9.9" ]] &&
		[[ $(wc -l < "$STUB_DIR/curl-calls") -eq 3 ]] &&
		grep -Fxq "https://api.github.com/repos/oven-sh/bun/releases/latest" "$STUB_DIR/curl-calls" &&
		grep -Fxq "https://github.com/oven-sh/bun/releases/download/bun-v9.9.9/SHASUMS256.txt" "$STUB_DIR/curl-calls" &&
		grep -Fxq "https://github.com/oven-sh/bun/releases/download/bun-v9.9.9/$asset" "$STUB_DIR/curl-calls"; then
		pass "verified $arch artifact installs with three downloads"
	else
		fail "verified $arch install (rc=$RC out=[$OUT] err=[$ERR])"
	fi
done
BUN_TEST_ARCH=x86_64

# 4. Version guard finds the binary through its own PATH prepend.
fresh_release
call
VERSION="$(env PATH="$T/bin:/usr/bin:/bin" HOME="$T/home" bash -c \
	'source "$1"; bun_version' _ "$SRC" 2>/dev/null)"
if [[ $VERSION == "bun fixture 9.9.9" ]]; then
	pass "bun_version resolves ~/.bun/bin without rc files"
else
	fail "version guard (got [$VERSION])"
fi

# 5. Tampered checksum file rejects the artifact.
fresh_release
make_metadata bad-sums
call
if [[ $RC -ne 0 && $ERR == *"checksum mismatch"* ]] && no_install; then
	pass "tampered checksum rejected, nothing installed"
else
	fail "tampered checksum (rc=$RC err=[$ERR])"
fi

# 6. Missing publisher checksum fails closed.
fresh_release
rm -f "$STUB_RELEASE/SHASUMS256.txt"
call
if [[ $RC -ne 0 && $ERR == *"cannot download checksum"* ]] && no_install; then
	pass "absent publisher checksum rejected"
else
	fail "absent checksum (rc=$RC err=[$ERR])"
fi

# 7/8. Missing asset and missing checksum entry in release metadata fail closed.
fresh_release
make_metadata no-assets
call
if [[ $RC -ne 0 && $ERR == *"error: bun:"* ]] && no_install; then
	pass "release without SHASUMS256.txt asset rejected"
else
	fail "missing checksum asset (rc=$RC err=[$ERR])"
fi
fresh_release
make_metadata no-tag
call
if [[ $RC -ne 0 && $ERR == *"error: bun:"* ]] && no_install; then
	pass "release without tag rejected"
else
	fail "missing tag (rc=$RC err=[$ERR])"
fi

# 9/10/11. Transport failures fail closed.
for marker in fail-latest fail-sums fail-asset; do
	fresh_release
	touch "$STUB_DIR/$marker"
	call
	if [[ $RC -ne 0 && $ERR == *"error: bun:"* ]] && no_install; then
		pass "$marker transport failure aborts"
	else
		fail "$marker (rc=$RC err=[$ERR])"
	fi
done

# 12. A valid archive without the bun binary must not report success.
fresh_release
rm -rf "$T/payload/bun-linux-x64.zip" && mkdir -p "$T/payload/bun-linux-x64.zip"
printf 'nope\n' > "$T/payload/bun-linux-x64.zip/README"
(cd "$T/payload" && rm -f "$STUB_RELEASE/bun-linux-x64.zip" && zip -qr "$STUB_RELEASE/bun-linux-x64.zip" bun-linux-x64.zip)
(cd "$STUB_RELEASE" && sha256sum bun-linux-x64.zip > SHASUMS256.txt)
make_metadata good
call
if [[ $RC -ne 0 && $ERR == *"has no bun binary"* ]] && no_install; then
	pass "archive missing bun rejected"
else
	fail "archive missing binary (rc=$RC err=[$ERR])"
fi

# 13. Unsupported architecture gets a named error.
fresh_release
BUN_TEST_ARCH=riscv64
call
if [[ $RC -ne 0 && $ERR == *"unsupported architecture: riscv64"* ]] && no_install; then
	pass "unsupported architecture named in error"
else
	fail "unsupported architecture (rc=$RC err=[$ERR])"
fi

[[ $FAILURES -eq 0 ]] || { printf '%s bun test(s) failed\n' "$FAILURES" >&2; exit 1; }
printf 'all bun tests passed\n'
