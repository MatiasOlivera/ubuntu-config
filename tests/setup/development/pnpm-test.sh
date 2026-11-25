#!/usr/bin/env bash
#
# pnpm-test.sh — hermetic use-case tests for issue #8.
# Black-box: asserts status, output, downloads and files, never helper names.
# curl and uname are local stubs; fixtures are built with real tar/sha256sum;
# HOME and TMPDIR are sandboxed. No network or system directories are touched.
# PNPM_SRC can override the script under test. Fail-closed: any failure exits 1.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${PNPM_SRC:-$ROOT/setup/development/pnpm.sh}"
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
	*/repos/pnpm/pnpm/releases/latest)
		[[ ! -f $STUB_DIR/fail-latest ]] || exit 22
		cp "$STUB_RELEASE/release.json" "$dest" ;;
	*/releases/download/*)
		[[ ! -f $STUB_DIR/fail-asset ]] || exit 22
		asset=${url##*/}
		[[ -f $STUB_RELEASE/$asset ]] || exit 22
		cp "$STUB_RELEASE/$asset" "$dest" ;;
	*) exit 22 ;;
esac
EOF

cat > "$T/bin/uname" <<'EOF'
#!/usr/bin/env bash
[[ $1 == -m ]] || exit 2
printf '%s\n' "${PNPM_TEST_ARCH:-x86_64}"
EOF
chmod +x "$T/bin/"*

make_metadata() {
	local mode=${1:-good} include=${2:-yes}
	python3 - "$STUB_RELEASE/release.json" "$STUB_RELEASE" "$mode" "$include" <<'PY'
import hashlib
import json
import os
import sys

out, release_dir, mode, include = sys.argv[1:]
assets = [{
    "name": "decoy.tar.gz",
    "digest": "sha256:" + "a" * 64,
    "browser_download_url": "https://github.com/pnpm/pnpm/releases/download/v12.21.0/decoy.tar.gz",
}]
if include == "yes":
    for name in ("pnpm-linux-x64.tar.gz", "pnpm-linux-arm64.tar.gz"):
        with open(os.path.join(release_dir, name), "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()
        item = {"name": name}
        if mode == "good":
            item["digest"] = "sha256:" + digest
        elif mode == "malformed":
            item["digest"] = "sha256:not-a-digest"
        elif mode == "badurl":
            item["digest"] = "sha256:" + digest
            item["browser_download_url"] = "https://evil.example/" + name
        # mode == "missing" omits the digest entirely
        if mode != "badurl":
            item["browser_download_url"] = (
                "https://github.com/pnpm/pnpm/releases/download/v12.21.0/" + name
            )
        assets.append(item)
with open(out, "w", encoding="utf-8") as f:
    json.dump({"tag_name": "v12.21.0", "assets": assets}, f)
PY
}

fresh_release() {
	rm -rf "$T/release" "$T/payload" "$T/home/.local" "$T/tmp"
	mkdir -p "$T/release" "$T/payload" "$T/home" "$T/tmp"
	rm -f "$STUB_DIR/curl-calls" "$STUB_DIR/fail-latest" "$STUB_DIR/fail-asset"
	local asset
	for asset in pnpm-linux-x64.tar.gz pnpm-linux-arm64.tar.gz; do
		printf '#!/usr/bin/env bash\nprintf "fake-pnpm 12.21.0\\n"\n' > "$T/payload/pnpm"
		chmod +x "$T/payload/pnpm"
		tar -czf "$T/release/$asset" -C "$T/payload" pnpm
	done
	make_metadata good yes
}

call() {
	OUT="$(env PATH="$T/bin:/usr/bin:/bin" HOME="$T/home" TMPDIR="$T/tmp" \
		STUB_DIR="$STUB_DIR" STUB_RELEASE="$STUB_RELEASE" \
		PNPM_TEST_ARCH="${PNPM_TEST_ARCH:-x86_64}" \
		bash "$SRC" install 2>"$T/stderr")"
	RC=$?
	ERR="$(cat "$T/stderr")"
}

binary() { printf '%s/.local/bin/pnpm\n' "$T/home"; }

no_install() { [[ ! -e $(binary) ]]; }

# 1. Skip guard: an installed pnpm short-circuits without any network call.
fresh_release
mkdir -p "$(dirname "$(binary)")"
printf '#!/usr/bin/env bash\nprintf "fake-pnpm 12.21.0\\n"\n' > "$(binary)"
chmod +x "$(binary)"
call
if [[ $RC -eq 0 && $OUT == *"skip: pnpm already installed"* &&
	! -s "$STUB_DIR/curl-calls" ]]; then
	pass "skip guard reports skip with no network"
else
	fail "skip guard (rc=$RC out=[$OUT] calls=[$(cat "$STUB_DIR/curl-calls" 2>/dev/null)])"
fi

# 2/3. Supported architectures select their asset and install a runnable binary.
for spec in "x86_64:pnpm-linux-x64.tar.gz" "aarch64:pnpm-linux-arm64.tar.gz"; do
	arch=${spec%%:*}
	asset=${spec#*:}
	fresh_release
	PNPM_TEST_ARCH=$arch
	call
	if [[ $RC -eq 0 && -x $(binary) && $OUT == *"installed: pnpm fake-pnpm 12.21.0"* &&
		"$($(binary) --version)" == "fake-pnpm 12.21.0" ]] &&
		[[ $(wc -l < "$STUB_DIR/curl-calls") -eq 2 ]] &&
		grep -Fxq "https://api.github.com/repos/pnpm/pnpm/releases/latest" "$STUB_DIR/curl-calls" &&
		grep -Fxq "https://github.com/pnpm/pnpm/releases/download/v12.21.0/$asset" "$STUB_DIR/curl-calls"; then
		pass "verified $arch artifact installs with two downloads"
	else
		fail "verified $arch install (rc=$RC out=[$OUT] err=[$ERR])"
	fi
done
PNPM_TEST_ARCH=x86_64

# 4. Version guard finds the binary through its own PATH prepend.
fresh_release
call
VERSION="$(env PATH="$T/bin:/usr/bin:/bin" HOME="$T/home" bash -c \
	'source "$1"; pnpm_version' _ "$SRC" 2>/dev/null)"
if [[ $VERSION == "fake-pnpm 12.21.0" ]]; then
	pass "pnpm_version resolves ~/.local/bin without rc files"
else
	fail "version guard (got [$VERSION])"
fi

# 5. Tampered bytes fail closed.
fresh_release
printf 'evil-bytes\n' > "$T/release/pnpm-linux-x64.tar.gz"
call
if [[ $RC -ne 0 && $ERR == *"checksum mismatch"* ]] && no_install; then
	pass "tampered tarball rejected, nothing installed"
else
	fail "tampered tarball (rc=$RC err=[$ERR])"
fi

# 6/7/8. Missing, malformed and untrusted metadata fail closed.
for mode in missing malformed badurl; do
	fresh_release
	make_metadata "$mode" yes
	call
	if [[ $RC -ne 0 && $ERR == *"error: pnpm:"* ]] && no_install; then
		pass "$mode digest/URL metadata rejected"
	else
		fail "$mode metadata (rc=$RC err=[$ERR])"
	fi
done

# 9. Missing asset in the release fails closed.
fresh_release
make_metadata good no
call
if [[ $RC -ne 0 && $ERR == *"pnpm-linux-x64.tar.gz"* ]] && no_install; then
	pass "absent release asset rejected"
else
	fail "absent asset (rc=$RC err=[$ERR])"
fi

# 10/11. Transport failures fail closed.
fresh_release
touch "$STUB_DIR/fail-latest"
call
if [[ $RC -ne 0 && $ERR == *"cannot download release metadata"* ]] && no_install; then
	pass "failed metadata download aborts"
else
	fail "failed metadata download (rc=$RC err=[$ERR])"
fi
fresh_release
touch "$STUB_DIR/fail-asset"
call
if [[ $RC -ne 0 && $ERR == *"cannot download pnpm-linux-x64.tar.gz"* ]] && no_install; then
	pass "failed asset download aborts"
else
	fail "failed asset download (rc=$RC err=[$ERR])"
fi

# 12. A valid archive without the pnpm binary must not report success.
fresh_release
rm -rf "$T/payload" && mkdir -p "$T/payload"
printf 'nope\n' > "$T/payload/README"
tar -czf "$T/release/pnpm-linux-x64.tar.gz" -C "$T/payload" README
make_metadata good yes
call
if [[ $RC -ne 0 && $ERR == *"has no pnpm binary"* ]] && no_install; then
	pass "archive missing pnpm rejected"
else
	fail "archive missing binary (rc=$RC err=[$ERR])"
fi

# 13. Unsupported architecture gets a named error.
fresh_release
PNPM_TEST_ARCH=riscv64
call
if [[ $RC -ne 0 && $ERR == *"unsupported architecture: riscv64"* ]] && no_install; then
	pass "unsupported architecture named in error"
else
	fail "unsupported architecture (rc=$RC err=[$ERR])"
fi

[[ $FAILURES -eq 0 ]] || { printf '%s pnpm test(s) failed\n' "$FAILURES" >&2; exit 1; }
printf 'all pnpm tests passed\n'
