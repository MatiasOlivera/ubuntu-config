#!/usr/bin/env bash
#
# chezmoi-test.sh — hermetic use-case tests for issue #93.
# chezmoi moves from the remote installer to a checksum-verified release
# artifact. curl, sudo and uname are local stubs; the archive is built from a
# local fake binary. HOME, TMPDIR and /usr/local/bin are sandboxed. No network,
# host install prefix or system-mutating command is touched.
# CHEZMOI_SRC overrides the script under test.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${CHEZMOI_SRC:-$ROOT/setup/essentials/chezmoi.sh}"
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
for b in awk bash basename cat chmod cp cut dirname env find grep head \
	gzip install mkdir mktemp mv python3 rm sed sh sha256sum sort tar tr wc; do
	src_bin="$(command -v "$b")" || { printf 'error: missing tool %s\n' "$b" >&2; exit 1; }
	ln -s "$src_bin" "$T/sysbin/$b"
done

cat >"$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
url= dest=
while [[ $# -gt 0 ]]; do
	case $1 in
	-o) dest=$2; shift 2 ;;
	-H) shift 2 ;;
	-*) shift ;;
	*) url=$1; shift ;;
	esac
done
printf '%s\n' "$url" >>"$STUB_DIR/curl-calls"
case $url in
	*api.github.com*/releases/latest)
		[[ -f $STUB_DIR/fail-metadata ]] && exit 22
		cp "$STUB_RELEASE/release.json" "$dest" ;;
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
args=()
for a in "$@"; do
	case $a in
	/usr/local/bin/*) a="$SANDBOX_ROOT$a" ;;
	esac
	args+=("$a")
done
exec "${args[@]}"
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

chmod +x "$T/bin/"*

cat >"$T/source-only.sh" <<'EOF'
#!/usr/bin/env bash
source "$1"
EOF

fresh_release() {
	"$REAL_RM" -rf "$T/release" "$T/payload" "$T/root" "$T/tmp"
	mkdir -p "$T/release" "$T/payload" "$T/root/usr/local/bin" "$T/tmp"
	"$REAL_RM" -f "$STUB_DIR/curl-calls" "$STUB_DIR/sudo-calls" \
		"$STUB_DIR/fail-metadata" "$STUB_DIR/fail-asset" "$STUB_DIR/arch"
	python3 - "$T/release" "$T/payload/chezmoi" <<'PY'
import hashlib
import json
import pathlib
import sys
import tarfile

out = pathlib.Path(sys.argv[1])
payload = pathlib.Path(sys.argv[2])
tag = "v2.74.2"
version = tag[1:]
prefix = "https://github.com/twpayne/chezmoi/releases/download/"
names = {
    "amd64": f"chezmoi_{version}_linux_amd64.tar.gz",
    "arm64": f"chezmoi_{version}_linux_arm64.tar.gz",
}
checksums_name = f"chezmoi_{version}_checksums.txt"
payload.write_text('#!/usr/bin/env bash\nprintf "chezmoi version 2.74.2\\n"\n', encoding="utf-8")
payload.chmod(0o755)

assets = []
for name in names.values():
    archive = out / name
    with tarfile.open(archive, "w:gz") as tf:
        tf.add(payload, arcname="chezmoi")
    assets.append({"name": name, "browser_download_url": f"{prefix}{tag}/{name}"})

lines = [f"{hashlib.sha256((out / name).read_bytes()).hexdigest()}  {name}"
         for name in names.values()]
lines += [f"{'b' * 64}  {names['amd64']}.sbom.json",
          f"{'c' * 64}  {checksums_name}"]
(out / checksums_name).write_text("\n".join(lines) + "\n", encoding="utf-8")
assets.append({"name": checksums_name,
               "browser_download_url": f"{prefix}{tag}/{checksums_name}"})
(out / "release.json").write_text(
    json.dumps({"tag_name": tag, "assets": assets}), encoding="utf-8"
)
PY
}

run() {
	local cmd=${1:-install}
	OUT="$(env PATH="$T/root/usr/local/bin:$T/bin:$T/sysbin" HOME="$T/home" \
		TMPDIR="$T/tmp" STUB_DIR="$STUB_DIR" STUB_RELEASE="$STUB_RELEASE" \
		SANDBOX_ROOT="$SANDBOX_ROOT" bash "$SRC" "$cmd" 2>"$T/stderr")"
	RC=$?
	ERR="$(cat "$T/stderr")"
}

no_install() { [[ ! -e $T/root/usr/local/bin/chezmoi ]]; }
tmp_empty() { [[ -z $(find "$T/tmp" -mindepth 1 -print -quit 2>/dev/null) ]]; }

# 1. Fresh amd64: verified artifact installed into /usr/local/bin.
fresh_release
run install
if [[ $RC -eq 0 && $OUT == *"installed: chezmoi"* &&
	-x $T/root/usr/local/bin/chezmoi ]] &&
	[[ "$("$T/root/usr/local/bin/chezmoi" --version)" == "chezmoi version 2.74.2" ]] &&
	tmp_empty; then
	pass 'fresh amd64 installs the verified binary into /usr/local/bin'
else
	fail "fresh amd64 (rc=$RC out=[$OUT] err=[$ERR])"
fi

if [[ $(wc -l < "$STUB_DIR/curl-calls" 2>/dev/null || printf '0\n') -eq 3 ]] &&
	! grep -qvE '(api\.github\.com/repos/twpayne/chezmoi/releases/latest|releases/download/v2\.74\.2/chezmoi_2\.74\.2_(checksums\.txt|linux_amd64\.tar\.gz))$' "$STUB_DIR/curl-calls"; then
	pass 'install downloads only metadata, checksums and the verified artifact'
else
	fail "download discipline (calls=[$(cat "$STUB_DIR/curl-calls" 2>/dev/null)])"
fi

# 2. Rerun with an installed binary skips before any network.
fresh_release
mkdir -p "$T/root/usr/local/bin"
printf '#!/usr/bin/env bash\nprintf "chezmoi version 2.74.2\\n"\n' >"$T/root/usr/local/bin/chezmoi"
chmod +x "$T/root/usr/local/bin/chezmoi"
run install
if [[ $RC -eq 0 && $OUT == *"skip: chezmoi already installed"* &&
	! -s "$STUB_DIR/curl-calls" ]]; then
	pass 'rerun skips an installed chezmoi without downloading anything'
else
	fail "skip guard (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 3. Tampered artifact: digest mismatch installs nothing.
fresh_release
printf 'evil bytes\n' >"$T/release/chezmoi_2.74.2_linux_amd64.tar.gz"
run install
if [[ $RC -ne 0 && $ERR == *"checksum mismatch"* ]] && no_install && tmp_empty; then
	pass 'tampered artifact fails closed without installing'
else
	fail "tampered artifact (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 4. Missing checksum material: parser fails closed before extraction.
fresh_release
python3 - "$T/release/chezmoi_2.74.2_checksums.txt" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
path.write_text("\n".join(l for l in lines if not l.endswith("linux_amd64.tar.gz")) + "\n",
                encoding="utf-8")
PY
run install
if [[ $RC -ne 0 && $ERR == *"error: chezmoi:"* ]] && no_install && tmp_empty; then
	pass 'missing integrity material fails closed'
else
	fail "missing checksum (rc=$RC out=[$OUT] err=[$ERR])"
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

# 6. Unsupported architecture is named before any download.
fresh_release
printf 'riscv64\n' >"$STUB_DIR/arch"
run install
if [[ $RC -ne 0 && $ERR == *"unsupported architecture: riscv64"* ]] &&
	no_install && tmp_empty && [[ ! -s "$STUB_DIR/curl-calls" ]]; then
	pass 'unsupported architecture fails before any download'
else
	fail "unsupported arch (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 7. arm64 selects the arm64 artifact.
fresh_release
printf 'aarch64\n' >"$STUB_DIR/arch"
run install
if [[ $RC -eq 0 && -x $T/root/usr/local/bin/chezmoi ]] &&
	grep -qF 'chezmoi_2.74.2_linux_arm64.tar.gz' "$STUB_DIR/curl-calls"; then
	pass 'arm64 uses the arm64 release artifact'
else
	fail "arm64 (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 8. Non-interactive shell and version dispatch both see the installed binary.
fresh_release
run install
if [[ $RC -eq 0 ]] &&
	[[ "$(env PATH="$T/root/usr/local/bin:$T/sysbin" chezmoi --version 2>/dev/null)" == "chezmoi version 2.74.2" ]]; then
	pass 'chezmoi is callable from a non-interactive shell'
else
	fail "non-interactive shell (rc=$RC out=[$OUT] err=[$ERR])"
fi
run version
if [[ $RC -eq 0 && $OUT == 'chezmoi version 2.74.2' ]]; then
	pass 'version command reports one line for the versions report'
else
	fail "version dispatch (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 9. Sourcing the script performs no install side effects.
fresh_release
env PATH="$T/bin:$T/sysbin" HOME="$T/home" TMPDIR="$T/tmp" \
	STUB_DIR="$STUB_DIR" STUB_RELEASE="$STUB_RELEASE" SANDBOX_ROOT="$SANDBOX_ROOT" \
	bash "$T/source-only.sh" "$SRC" >/dev/null 2>&1
source_rc=$?
if [[ $source_rc -eq 0 && ! -e "$STUB_DIR/curl-calls" && ! -e "$STUB_DIR/sudo-calls" ]]; then
	pass 'sourcing the script writes nothing'
else
	fail "source-only (rc=$source_rc)"
fi

if (( FAILURES > 0 )); then
	printf '%d test(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all chezmoi verified-artifact tests passed\n'
