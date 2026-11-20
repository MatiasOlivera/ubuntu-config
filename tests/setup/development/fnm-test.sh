#!/usr/bin/env bash
#
# fnm-test.sh — hermetic use-case tests for issue #47.
# Black-box assertions cover status, output, network calls, and files. curl,
# sudo, uname, and unzip are local stubs; HOME and TMPDIR are sandboxed.
# Fixtures contain a tiny ZIP with a real sha256sum digest. No network or
# system directories are touched. FNM_SRC can override the script under test.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${FNM_SRC:-$ROOT/setup/development/fnm/install-fnm.sh}"
FAILURES=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	printf 'ok: %s\n' "$1"
}

if ! command -v python3 >/dev/null 2>&1; then
	printf 'error: python3 is required to run fnm-test.sh\n' >&2
	exit 1
fi

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/sysbin" "$T/home" "$T/tmp" "$T/stubs"
export STUB_DIR="$T/stubs"

# Closed set of real tools used by the installer. Network, sudo, uname, and
# unzip are provided by local stubs in $T/bin.
for b in awk basename bash cat chmod cmp cp dirname env find grep head ln mkdir mktemp mv python3 rm sha256sum tr uname; do
	ln -s "$(command -v "$b")" "$T/sysbin/$b"
done

cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
dest="" prev="" url=""
for arg in "$@"; do
	[[ $prev == "-o" ]] && dest=$arg
	case $arg in http://* | https://*) url=$arg ;; esac
	prev=$arg
done
printf '%s\n' "$url" >> "$STUB_DIR/curl-calls"
case $url in
	*/repos/Schniz/fnm/releases/latest)
		if [[ -f $STUB_DIR/fail-api ]]; then
			[[ -z $dest ]] || printf '{partial' > "$dest"
			exit 22
		fi
		if [[ -n $dest ]]; then
			cp "$STUB_DIR/release.json" "$dest"
		else
			cat "$STUB_DIR/release.json"
		fi
		;;
	*/releases/download/*)
		[[ -n $dest ]] || exit 22
		if [[ -f $STUB_DIR/fail-asset ]]; then
			printf 'partial artifact bytes\n' > "$dest"
			exit 22
		fi
		if [[ -f $STUB_DIR/tamper-asset ]]; then
			printf 'tampered artifact bytes\n' > "$dest"
		else
			cp "$STUB_DIR/artifact.zip" "$dest"
		fi
		;;
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
case $1 in
	-m) printf '%s\n' "${FNM_TEST_ARCH:-x86_64}" ;;
	*) exit 2 ;;
esac
EOF

cat > "$T/bin/unzip" <<'EOF'
#!/usr/bin/env bash
case $1 in
-p)
	[[ $# -eq 3 ]] || exit 2
	python3 - "$2" "$3" <<'PYEOF'
import sys
import zipfile
try:
    with zipfile.ZipFile(sys.argv[1]) as archive:
        sys.stdout.buffer.write(archive.read(sys.argv[2]))
except (KeyError, OSError, zipfile.BadZipFile):
    sys.exit(1)
PYEOF
	;;
-tqq)
	[[ $# -eq 2 ]] || exit 2
	python3 - "$2" <<'PYEOF'
import sys
import zipfile
try:
    with zipfile.ZipFile(sys.argv[1]) as archive:
        if archive.testzip() is not None:
            sys.exit(1)
except (OSError, zipfile.BadZipFile):
    sys.exit(1)
PYEOF
	;;
*) exit 2 ;;
esac
EOF
chmod +x "$T/bin/"*

make_artifact() {
	local asset=$1 layout=${2:-nested} member
	member="${asset%.zip}/fnm"
	[[ $layout == root ]] && member=fnm
	python3 - "$STUB_DIR/artifact.zip" "$STUB_DIR/fnm-fixture" "$member" <<'PYEOF'
import sys
import zipfile
out, expected, member = sys.argv[1:]
payload = b"#!/usr/bin/env bash\nprintf 'fnm fixture 9.9.9\\n'\n"
with open(expected, "wb") as f:
    f.write(payload)
with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as archive:
    archive.writestr(member, payload)
PYEOF
}

make_metadata() {
	local asset=$1 digest_mode=${2:-good} include_asset=${3:-yes}
	local digest
	digest="$(sha256sum "$STUB_DIR/artifact.zip")"
	digest=${digest%% *}
	case $digest_mode in
		good) digest="sha256:$digest" ;;
		missing) digest="" ;;
		malformed) digest="sha256:not-a-digest" ;;
		*) return 2 ;;
	esac
	python3 - "$STUB_DIR/release.json" "$asset" "$digest" "$include_asset" <<'PYEOF'
import json
import sys
out, name, digest, include_asset = sys.argv[1:]
assets = [{
    "name": "decoy.zip",
    "digest": "sha256:" + "a" * 64,
    "browser_download_url": "https://github.com/Schniz/fnm/releases/download/v9.9.9/decoy.zip",
}]
if include_asset == "yes":
    item = {
        "name": name,
        "browser_download_url": "https://github.com/Schniz/fnm/releases/download/v9.9.9/" + name,
    }
    if digest:
        item["digest"] = digest
    assets.append(item)
with open(out, "w", encoding="utf-8") as f:
    json.dump({"tag_name": "v9.9.9", "assets": assets}, f)
PYEOF
}

fresh_case() {
	rm -rf "$T/home" "$T/tmp"
	mkdir -p "$T/home" "$T/tmp"
	rm -f "$STUB_DIR/curl-calls" "$STUB_DIR/sudo-calls" \
		"$STUB_DIR/fail-api" "$STUB_DIR/fail-asset" "$STUB_DIR/fail-sudo" \
		"$STUB_DIR/tamper-asset"
}

prepare_case() {
	local arch=${1:-x86_64} layout=${2:-nested} asset
	fresh_case
	case $arch in
		x86_64 | amd64) asset=fnm-linux.zip ;;
		aarch* | arm64 | armv8*) asset=fnm-arm64.zip ;;
		arm | armv7*) asset=fnm-arm32.zip ;;
		*) asset=fnm-linux.zip ;;
	esac
	make_artifact "$asset" "$layout"
	make_metadata "$asset"
	export FNM_TEST_ARCH="$arch"
}

call_installer() {
	OUT=""
	ERR=""
	RC=0
	if OUT="$(env PATH="$T/bin:$T/sysbin" HOME="$T/home" TMPDIR="$T/tmp" \
		STUB_DIR="$STUB_DIR" FNM_TEST_ARCH="$FNM_TEST_ARCH" \
		bash "$SRC" install 2>"$T/stderr")"; then
		RC=0
	else
		RC=$?
	fi
	ERR="$(cat "$T/stderr")"
}

binary_path() {
	printf '%s/.local/share/fnm/fnm\n' "$T/home"
}

tmp_is_empty() {
	[[ -z $(find "$T/tmp" -mindepth 1 -print -quit) ]]
}

assert_install() {
	local arch=$1 asset=$2 binary
	prepare_case "$arch" nested
	binary="$(binary_path)"
	call_installer
	if [[ $RC -eq 0 && -x $binary &&
		$OUT == *"installed: fnm"* && $("$binary" --version) == "fnm fixture 9.9.9" ]] &&
		cmp -s "$binary" "$STUB_DIR/fnm-fixture" &&
		grep -Fxq "https://api.github.com/repos/Schniz/fnm/releases/latest" "$STUB_DIR/curl-calls" &&
		[[ $(wc -l < "$STUB_DIR/curl-calls") -eq 2 ]] &&
		grep -Fxq "https://github.com/Schniz/fnm/releases/download/v9.9.9/$asset" "$STUB_DIR/curl-calls"; then
		pass "verified $arch artifact installs and runs"
	else
		fail "verified $arch install (rc=$RC out=[$OUT] err=[$ERR])"
	fi
}

# 1. Existing installation skips before dependency setup or network access.
fresh_case
mkdir -p "$T/home/.local/share/fnm"
cat > "$(binary_path)" <<'EOF'
#!/usr/bin/env bash
printf 'fnm fixture 9.9.9\n'
EOF
chmod +x "$(binary_path)"
call_installer
if [[ $RC -eq 0 && $OUT == *"skip: fnm already installed"* &&
	! -s "$STUB_DIR/curl-calls" && ! -s "$STUB_DIR/sudo-calls" ]]; then
	pass "skip guard reports skip with no network or dependency command"
else
	fail "skip guard (rc=$RC out=[$OUT])"
fi

# 2. Supported architectures select their matching release asset.
assert_install x86_64 fnm-linux.zip
assert_install aarch64 fnm-arm64.zip
assert_install armv8l fnm-arm64.zip
assert_install armv7l fnm-arm32.zip

# 3. The root-entry ZIP layout used by some releases is accepted too.
prepare_case x86_64 root
call_installer
if [[ $RC -eq 0 && -x $(binary_path) ]]; then
	pass "root-entry ZIP layout installs"
else
	fail "root-entry ZIP layout (rc=$RC err=[$ERR])"
fi

# 4. Missing asset and missing or malformed digest all fail closed.
prepare_case x86_64 nested
make_metadata fnm-linux.zip good no
call_installer
	if [[ $RC -ne 0 && $ERR == *asset* && ! -e $(binary_path) ]] && tmp_is_empty; then
	pass "release without matching asset is rejected"
else
	fail "missing asset (rc=$RC err=[$ERR])"
fi

for digest_mode in missing malformed; do
	prepare_case x86_64 nested
	make_metadata fnm-linux.zip "$digest_mode"
	call_installer
	if [[ $RC -ne 0 && $ERR == *digest* && ! -e $(binary_path) ]] && tmp_is_empty; then
		pass "$digest_mode digest is rejected"
	else
		fail "$digest_mode digest (rc=$RC err=[$ERR])"
	fi
done

# Malformed release contracts fail before following an untrusted URL.
prepare_case x86_64 nested
python3 - "$STUB_DIR/release.json" <<'PYEOF'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    release = json.load(f)
del release["tag_name"]
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(release, f)
PYEOF
call_installer
if [[ $RC -ne 0 && $ERR == *"tag"* && ! -e $(binary_path) ]] && tmp_is_empty; then
	pass "release without a tag is rejected"
else
	fail "missing tag (rc=$RC err=[$ERR])"
fi

prepare_case x86_64 nested
python3 - "$STUB_DIR/release.json" <<'PYEOF'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    release = json.load(f)
release["assets"].append(release["assets"][-1].copy())
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(release, f)
PYEOF
call_installer
if [[ $RC -ne 0 && $ERR == *"duplicate assets"* && ! -e $(binary_path) ]]; then
	pass "duplicate matching assets are rejected"
else
	fail "duplicate assets (rc=$RC err=[$ERR])"
fi

prepare_case x86_64 nested
python3 - "$STUB_DIR/release.json" <<'PYEOF'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    release = json.load(f)
release["assets"][-1]["browser_download_url"] = "https://example.invalid/fnm-linux.zip"
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(release, f)
PYEOF
call_installer
if [[ $RC -ne 0 && $ERR == *"download URL"* && ! -e $(binary_path) ]] &&
	[[ $(wc -l < "$STUB_DIR/curl-calls") -eq 1 ]] && tmp_is_empty; then
	pass "non-GitHub asset URLs are rejected before download"
else
	fail "invalid asset URL (rc=$RC err=[$ERR])"
fi

# 5. Malformed release metadata and API/asset transport failures fail closed.
prepare_case x86_64 nested
printf '{malformed json' > "$STUB_DIR/release.json"
call_installer
if [[ $RC -ne 0 && $ERR == *release* && ! -e $(binary_path) ]] && tmp_is_empty; then
	pass "malformed release metadata is rejected"
else
	fail "malformed metadata (rc=$RC err=[$ERR])"
fi

for failure in api asset; do
	prepare_case x86_64 nested
	touch "$STUB_DIR/fail-$failure"
	call_installer
	expected=release
	[[ $failure == asset ]] && expected=download
	if [[ $RC -ne 0 && $ERR == *"$expected"* && ! -e $(binary_path) ]] && tmp_is_empty; then
		pass "$failure transport failure leaves fnm uninstalled"
	else
		fail "$failure transport failure (rc=$RC err=[$ERR])"
	fi
done

# Failed dependency installation stops before requesting release metadata.
prepare_case x86_64 nested
touch "$STUB_DIR/fail-sudo"
call_installer
if [[ $RC -ne 0 && ! -s "$STUB_DIR/curl-calls" && ! -e $(binary_path) ]]; then
	pass "dependency failure stops before network or install"
else
	fail "dependency failure (rc=$RC err=[$ERR])"
fi

# Missing required network tooling is reported before making a request.
prepare_case x86_64 nested
mv "$T/bin/curl" "$T/bin/curl.disabled"
call_installer
mv "$T/bin/curl.disabled" "$T/bin/curl"
if [[ $RC -ne 0 && $ERR == *"curl is required"* &&
	! -s "$STUB_DIR/curl-calls" && ! -e $(binary_path) ]]; then
	pass "missing curl is named and fails closed"
else
	fail "missing curl (rc=$RC err=[$ERR])"
fi

# 6. Tampered artifact, invalid ZIP, and ZIP without fnm fail without replacing
# an existing but non-runnable binary.
for failure in tamper invalid missing-fnm; do
	prepare_case x86_64 nested
	mkdir -p "$T/home/.local/share/fnm"
	printf 'existing bytes\n' > "$(binary_path)"
	before="$(sha256sum "$(binary_path)")"
	case $failure in
		tamper) touch "$STUB_DIR/tamper-asset"; expected=checksum ;;
		invalid)
			printf 'not a zip\n' > "$STUB_DIR/artifact.zip"
			make_metadata fnm-linux.zip
			expected=archive
			;;
		missing-fnm)
			python3 - "$STUB_DIR/artifact.zip" <<'PYEOF'
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr("README.txt", "no executable here")
PYEOF
			make_metadata fnm-linux.zip
			expected=fnm
			;;
	esac
	call_installer
	after="$(sha256sum "$(binary_path)")"
	if [[ $RC -ne 0 && $before == "$after" && $ERR == *"$expected"* ]] && tmp_is_empty; then
		pass "$failure artifact rejected without changing existing binary"
	else
		fail "$failure artifact (rc=$RC err=[$ERR] before=[$before] after=[$after])"
	fi
done

# 7. Unknown architecture fails before apt or any release request.
prepare_case riscv64 nested
call_installer
if [[ $RC -ne 0 && $ERR == *"unsupported architecture"* &&
	! -s "$STUB_DIR/curl-calls" && ! -s "$STUB_DIR/sudo-calls" ]] && tmp_is_empty; then
	pass "unsupported architecture fails before dependencies or network"
else
	fail "unsupported architecture (rc=$RC err=[$ERR])"
fi

if (( FAILURES )); then
	printf '%d failure(s)\n' "$FAILURES" >&2
	exit 1
fi
printf 'all tests passed\n'
