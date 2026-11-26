#!/usr/bin/env bash
#
# bitwarden-cli-test.sh — hermetic use-case tests for issue #90.
# The CLI moves from snap to a checksum-verified release artifact. curl, sudo,
# apt, uname and ln are local stubs; the release zip is built from a local fake
# binary; HOME, TMPDIR and the /usr/local/bin symlink target are sandboxed.
# No network, host install prefix or system-mutating command is touched.
# BW_SRC overrides the script under test.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${BW_SRC:-$ROOT/setup/development/bitwarden-cli.sh}"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
REAL_RM="$(command -v rm)"
trap '"$REAL_RM" -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/sysbin" "$T/stubs" "$T/release" "$T/payload" \
	"$T/home" "$T/tmp" "$T/root/usr/local/bin"
STUB_DIR="$T/stubs"
STUB_RELEASE="$T/release"
SANDBOX_ROOT="$T/root"
export STUB_DIR STUB_RELEASE SANDBOX_ROOT

# Closed set of real tools; anything touching network/system is stubbed in $T/bin.
for b in awk bash basename cat chmod cp cut diff dirname env find grep head \
	mkdir mktemp mv python3 rm sha256sum sort tail tr unzip; do
	src_bin="$(command -v "$b")" || { printf 'error: missing tool %s\n' "$b" >&2; exit 1; }
	ln -s "$src_bin" "$T/sysbin/$b"
done

cat >"$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
url= dest=
while [[ $# -gt 0 ]]; do
	case $1 in
	-o) dest=$2; shift 2 ;;
	-*) shift ;;
	*) url=$1; shift ;;
	esac
done
printf '%s\n' "$url" >>"$STUB_DIR/curl-calls"
case $url in
	*api.github.com*/releases*)
		[[ -f $STUB_DIR/fail-metadata ]] && exit 22
		cp "$STUB_RELEASE/releases.json" "$dest" ;;
	*/releases/download/*)
		[[ -f $STUB_DIR/fail-asset ]] && exit 22
		asset=${url##*/}
		[[ -f $STUB_RELEASE/$asset ]] || exit 22
		cp "$STUB_RELEASE/$asset" "$dest" ;;
	*) exit 22 ;;
esac
EOF

cat >"$T/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_DIR/sudo-calls"
exec "$@"
EOF

cat >"$T/bin/apt" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_DIR/apt-calls"
exit 0
EOF

cat >"$T/bin/uname" <<'EOF'
#!/usr/bin/env bash
arch=x86_64
[[ -f $STUB_DIR/arch ]] && arch="$(cat "$STUB_DIR/arch")"
case $1 in
	-m) printf '%s\n' "$arch" ;;
	-s) printf 'Linux\n' ;;
	*) printf '%s\n' "$arch" ;;
esac
EOF

# Redirect only the absolute /usr/local/bin target into the sandbox.
cat >"$T/bin/ln" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_DIR/ln-calls"
args=()
for a in "$@"; do
	case $a in
	/usr/local/bin/*) a="$SANDBOX_ROOT$a" ;;
	esac
	args+=("$a")
done
exec /bin/ln "${args[@]}"
EOF

cat >"$T/bin/bw" <<'EOF'
#!/usr/bin/env bash
printf 'snap-bw 1.2.3\n'
EOF

chmod +x "$T/bin/"*

cat >"$T/source-only.sh" <<'EOF'
#!/usr/bin/env bash
source "$1"
EOF

# Build both release zips, a fake bw binary and matching GitHub-style digests.
fresh_release() {
	"$REAL_RM" -rf "$T/release" "$T/payload" "$T/home/.local" "$T/tmp" "$T/root"
	mkdir -p "$T/release" "$T/payload" "$T/home" "$T/tmp" "$T/root/usr/local/bin"
	"$REAL_RM" -f "$STUB_DIR/curl-calls" "$STUB_DIR/sudo-calls" \
		"$STUB_DIR/apt-calls" "$STUB_DIR/ln-calls" "$STUB_DIR/fail-metadata" \
		"$STUB_DIR/fail-asset" "$STUB_DIR/bad-zip" "$STUB_DIR/no-bw" \
		"$STUB_DIR/arch"
	printf '#!/usr/bin/env bash\nprintf "verified-bw 2026.11.1\\n"\n' >"$T/payload/bw"
	chmod +x "$T/payload/bw"
	python3 - "$T/release" "$T/payload/bw" <<'PY'
import hashlib
import json
import pathlib
import sys
import zipfile

out = pathlib.Path(sys.argv[1])
payload = pathlib.Path(sys.argv[2])
names = {
    "amd64": "bw-bit-linux-2026.11.1.zip",
    "arm64": "bw-bit-linux-arm64-2026.11.1.zip",
}
assets = []
for arch, name in names.items():
    archive = out / name
    with zipfile.ZipFile(archive, "w") as zf:
        zf.write(payload, "bw")
    assets.append({
        "name": name,
        "browser_download_url": (
            "https://github.com/bitwarden/clients/releases/download/"
            f"cli-v2026.11.1/{name}"
        ),
        "digest": "sha256:" + hashlib.sha256(archive.read_bytes()).hexdigest(),
    })
releases = [
    {"tag_name": "web-v2026.11.2", "assets": []},
    {"tag_name": "cli-v2026.11.1", "assets": assets},
]
(out / "releases.json").write_text(json.dumps(releases), encoding="utf-8")
PY
}

run() {
	local cmd=${1:-install}
	OUT="$(env PATH="$T/bin:$T/sysbin" HOME="$T/home" TMPDIR="$T/tmp" \
		STUB_DIR="$STUB_DIR" STUB_RELEASE="$STUB_RELEASE" \
		SANDBOX_ROOT="$SANDBOX_ROOT" bash "$SRC" "$cmd" 2>"$T/stderr")"
	RC=$?
	ERR="$(cat "$T/stderr")"
}

no_install() { [[ ! -e $T/home/.local/bin/bw ]]; }
tmp_empty() { [[ -z $(find "$T/tmp" -mindepth 1 -print -quit 2>/dev/null) ]]; }
curl_urls() { sed 's/?.*//' "$STUB_DIR/curl-calls" 2>/dev/null | sort; }

# 1. Fresh amd64: verified artifact installed, symlink created, only two downloads.
fresh_release
run install
if [[ $RC -eq 0 && $OUT == *"installed: bitwarden-cli"* &&
	-x $T/home/.local/bin/bw &&
	-x $T/root/usr/local/bin/bw ]] &&
	[[ "$("$T/home/.local/bin/bw" --version)" == "verified-bw 2026.11.1" ]] &&
	grep -qF -- "-sf $T/home/.local/bin/bw /usr/local/bin/bw" "$STUB_DIR/ln-calls" &&
	grep -qF 'install -y unzip' "$STUB_DIR/apt-calls" && tmp_empty; then
	pass 'fresh amd64 installs the verified binary and links it into /usr/local/bin'
else
	fail "fresh amd64 (rc=$RC out=[$OUT] err=[$ERR])"
fi

if [[ $(wc -l < "$STUB_DIR/curl-calls" 2>/dev/null || printf '0\n') -eq 2 ]] &&
	! grep -qvE '(api\.github\.com/repos/bitwarden/clients/releases|releases/download/cli-v2026\.11\.1/bw-bit-linux-2026\.11\.1\.zip)$' "$STUB_DIR/curl-calls"; then
	pass 'install downloads only release metadata and the verified artifact'
else
	fail "download discipline (calls=[$(cat "$STUB_DIR/curl-calls" 2>/dev/null)])"
fi

# 2. Rerun with an installed verified binary skips before any network.
fresh_release
mkdir -p "$T/home/.local/bin"
printf '#!/usr/bin/env bash\nprintf "verified-bw 2026.11.1\\n"\n' >"$T/home/.local/bin/bw"
chmod +x "$T/home/.local/bin/bw"
run install
if [[ $RC -eq 0 && $OUT == *"skip: bitwarden-cli already installed"* &&
	! -s "$STUB_DIR/curl-calls" ]]; then
	pass 'rerun skips an installed CLI without downloading anything'
else
	fail "skip guard (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 3. Tampered artifact: digest mismatch installs nothing.
fresh_release
printf 'evil bytes\n' >"$T/release/bw-bit-linux-2026.11.1.zip"
run install
if [[ $RC -ne 0 && $ERR == *"checksum mismatch"* ]] && no_install && tmp_empty; then
	pass 'tampered artifact fails closed without installing'
else
	fail "tampered artifact (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 4. Missing digest material: fail closed before extraction.
fresh_release
python3 - "$T/release/releases.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
releases = json.loads(path.read_text(encoding="utf-8"))
releases[1]["assets"][0]["digest"] = ""
path.write_text(json.dumps(releases), encoding="utf-8")
PY
run install
if [[ $RC -ne 0 && $ERR == *"error: bitwarden-cli:"* ]] && no_install && tmp_empty; then
	pass 'missing integrity material fails closed'
else
	fail "missing digest (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 5. Metadata download failure is loud and leaves nothing installed.
fresh_release
: >"$STUB_DIR/fail-metadata"
run install
if [[ $RC -ne 0 && $ERR == *"cannot download release metadata"* ]] && no_install && tmp_empty; then
	pass 'metadata download failure fails closed'
else
	fail "metadata failure (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 6. Artifact download failure is loud and leaves nothing installed.
fresh_release
: >"$STUB_DIR/fail-asset"
run install
if [[ $RC -ne 0 && $ERR == *"cannot download bw-bit-linux-2026.11.1.zip"* ]] && no_install && tmp_empty; then
	pass 'artifact download failure fails closed'
else
	fail "artifact failure (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 7. Invalid zip: a checksum-valid artifact still cannot install a bad archive.
fresh_release
printf 'not a zip\n' >"$T/release/bw-bit-linux-2026.11.1.zip"
python3 - "$T/release" "$T/release/bw-bit-linux-2026.11.1.zip" <<'PY'
import hashlib
import json
import pathlib
import sys

release = pathlib.Path(sys.argv[1])
archive = pathlib.Path(sys.argv[2])
data = json.loads((release / "releases.json").read_text(encoding="utf-8"))
data[1]["assets"][0]["digest"] = "sha256:" + hashlib.sha256(
    archive.read_bytes()
).hexdigest()
(release / "releases.json").write_text(json.dumps(data), encoding="utf-8")
PY
run install
if [[ $RC -ne 0 && $ERR == *"invalid ZIP archive"* ]] && no_install && tmp_empty; then
	pass 'invalid archive fails closed despite a matching digest'
else
	fail "invalid archive (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 8. Unsupported architecture is named before any artifact is downloaded.
fresh_release
printf 'riscv64\n' >"$STUB_DIR/arch"
run install
if [[ $RC -ne 0 && $ERR == *"unsupported architecture: riscv64"* ]] &&
	no_install && tmp_empty && ! -s "$STUB_DIR/curl-calls"; then
	pass 'unsupported architecture fails before any download'
else
	fail "unsupported arch (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 9. arm64 selects the arm64 asset.
fresh_release
printf 'aarch64\n' >"$STUB_DIR/arch"
run install
if [[ $RC -eq 0 && -x $T/home/.local/bin/bw ]] &&
	grep -qF 'bw-bit-linux-arm64-2026.11.1.zip' "$STUB_DIR/curl-calls"; then
	pass 'arm64 uses the arm64 release artifact'
else
	fail "arm64 (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 10. An existing snap bw on PATH does not suppress the verified install.
fresh_release
run install
if [[ $RC -eq 0 && $OUT == *"verified-bw 2026.11.1"* &&
	"$("$T/home/.local/bin/bw" --version)" == "verified-bw 2026.11.1" ]]; then
	pass 'snap-installed bw on PATH does not satisfy the verified-install guard'
else
	fail "existing snap (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 11. Version dispatch reads only the verified install.
run version
if [[ $RC -eq 0 && $OUT == 'verified-bw 2026.11.1' ]]; then
	pass 'version command reports the verified install'
else
	fail "version dispatch (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 12. Sourcing the script performs no install side effects.
fresh_release
env PATH="$T/bin:$T/sysbin" HOME="$T/home" TMPDIR="$T/tmp" \
	STUB_DIR="$STUB_DIR" STUB_RELEASE="$STUB_RELEASE" SANDBOX_ROOT="$SANDBOX_ROOT" \
	bash "$T/source-only.sh" "$SRC" >/dev/null 2>&1
source_rc=$?
if [[ $source_rc -eq 0 && ! -e "$STUB_DIR/curl-calls" && ! -e "$STUB_DIR/apt-calls" ]]; then
	pass 'sourcing the script writes nothing'
else
	fail "source-only (rc=$source_rc)"
fi

if (( FAILURES > 0 )); then
	printf '%d test(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all bitwarden-cli verified-artifact tests passed\n'
