#!/usr/bin/env bash
#
# handy-test.sh — hermetic use-case tests for issue #88.
# Handy moves from a raw vendor .deb to a minisign-verified release artifact.
# curl, minisign, sudo, apt, dpkg and uname are local stubs; every path is
# sandboxed under TMPDIR: no network, no host changes.
# HANDY_SRC overrides the script under test.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${HANDY_SRC:-$ROOT/setup/desktop-apps/handy/handy.sh}"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
REAL_RM="$(command -v rm)"
trap '"$REAL_RM" -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/sysbin" "$T/stubs" "$T/release" "$T/tmp"
STUB_DIR="$T/stubs"
STUB_RELEASE="$T/release"
export STUB_DIR STUB_RELEASE REAL_RM

# Closed set of real tools the script and stubs use. Everything that touches
# the network or the system is replaced by a stub in $T/bin.
for b in awk basename bash base64 cat cmp cp diff dirname env find grep head mkdir mktemp mv rm sort tr; do
	ln -s "$(command -v "$b")" "$T/sysbin/$b"
done

printf 'fixture amd64 deb bytes\n' >"$STUB_RELEASE/Handy_0.10.2_amd64.deb"
printf 'fixture arm64 deb bytes\n' >"$STUB_RELEASE/Handy_0.10.2_arm64.deb"
printf 'Zml4dHVyZSBzaWduYXR1cmUgYnl0ZXMK' >"$STUB_RELEASE/Handy_0.10.2_amd64.deb.sig"
printf 'Zml4dHVyZSBzaWduYXR1cmUgYnl0ZXMK' >"$STUB_RELEASE/Handy_0.10.2_arm64.deb.sig"

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
printf '%s %s\n' "$url" "$dest" >>"$STUB_DIR/curl-calls"
[[ -f $STUB_DIR/curl_fail ]] && exit 22
case $url in
*/Handy_*.deb.sig)
	[[ -f $STUB_DIR/missing_sig ]] && exit 22
	cp "$STUB_RELEASE/${url##*/}" "$dest" ;;
*/Handy_*.deb)
	cp "$STUB_RELEASE/${url##*/}" "$dest" ;;
*) exit 22 ;;
esac
EOF

cat >"$T/bin/minisign" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_DIR/minisign-calls"
[[ -f $STUB_DIR/minisign_fail ]] && exit 1
exit 0
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

cat >"$T/bin/dpkg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_DIR/dpkg-calls"
[[ -f $STUB_DIR/dpkg_installed ]] && printf 'Version: 0.10.2\n'
exit 0
EOF

cat >"$T/bin/uname" <<'EOF'
#!/usr/bin/env bash
[[ -f $STUB_DIR/arch ]] && cat "$STUB_DIR/arch" || printf 'x86_64\n'
EOF

chmod +x "$T/bin/"*

cat >"$T/source-only.sh" <<'EOF'
#!/usr/bin/env bash
source "$1"
EOF

cat >"$T/expected-amd64" <<'EOF'
https://github.com/cjpais/Handy/releases/download/v0.10.2/Handy_0.10.2_amd64.deb
https://github.com/cjpais/Handy/releases/download/v0.10.2/Handy_0.10.2_amd64.deb.sig
EOF
cat >"$T/expected-arm64" <<'EOF'
https://github.com/cjpais/Handy/releases/download/v0.10.2/Handy_0.10.2_arm64.deb
https://github.com/cjpais/Handy/releases/download/v0.10.2/Handy_0.10.2_arm64.deb.sig
EOF

reset_case() {
	"$REAL_RM" -rf "$T/tmp"
	mkdir -p "$T/tmp"
	"$REAL_RM" -f "$STUB_DIR/curl-calls" "$STUB_DIR/minisign-calls" \
		"$STUB_DIR/sudo-calls" "$STUB_DIR/apt-calls" "$STUB_DIR/dpkg-calls" \
		"$STUB_DIR/minisign_fail" "$STUB_DIR/missing_sig" "$STUB_DIR/dpkg_installed" \
		"$STUB_DIR/arch" "$STUB_DIR/curl_fail"
}

run() {
	local command=$1
	OUT="" ERR="" RC=0
	if OUT="$(env PATH="$T/bin:$T/sysbin" TMPDIR="$T/tmp" HOME="$T" \
		STUB_DIR="$STUB_DIR" STUB_RELEASE="$STUB_RELEASE" \
		bash "$SRC" "$command" 2>"$T/stderr")"; then
		RC=0
	else
		RC=$?
	fi
	ERR="$(cat "$T/stderr")"
}

curl_urls() { grep -oE 'https://[^ ]+' "$STUB_DIR/curl-calls" 2>/dev/null | sort; }
apt_has() { grep -Fq -- "$1" "$STUB_DIR/apt-calls" 2>/dev/null; }
apt_installs_deb() { grep -qE '^install -y /.*Handy_0\.10\.2_.*\.deb$' "$STUB_DIR/apt-calls" 2>/dev/null; }
tmp_empty() { [[ -z $(find "$T/tmp" -mindepth 1 -print -quit 2>/dev/null) ]]; }

# 1. Fresh amd64: pinned artifacts only, signature verified before apt install.
reset_case
run install
if [[ $RC -eq 0 ]] && diff -u "$T/expected-amd64" <(curl_urls) >/dev/null &&
	grep -qE -- '-Vm [^ ]+\.deb' "$STUB_DIR/minisign-calls" &&
	grep -qE -- '-p [^ ]+handy\.pub' "$STUB_DIR/minisign-calls" &&
	grep -qE -- '-x [^ ]+\.minisig' "$STUB_DIR/minisign-calls" &&
	apt_has 'install -y minisign' && apt_installs_deb && tmp_empty; then
	pass 'fresh amd64 install downloads pinned artifacts, verifies, then installs'
else
	fail "fresh amd64 (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 2. Failed signature: no deb reaches apt and the temp dir is removed.
reset_case
: >"$STUB_DIR/minisign_fail"
run install
if [[ $RC -ne 0 ]] && ! apt_installs_deb && tmp_empty &&
	grep -q 'signature mismatch' "$T/stderr"; then
	pass 'signature failure fails closed without installing the deb'
else
	fail "signature failure (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 3. Publisher omits the signature asset: fail closed, no deb reaches apt.
reset_case
: >"$STUB_DIR/missing_sig"
run install
if [[ $RC -ne 0 ]] && ! apt_installs_deb && tmp_empty &&
	grep -q 'cannot download signature' "$T/stderr"; then
	pass 'missing signature asset fails closed'
else
	fail "missing signature (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 4. Installed Handy: version guard skips before any network or apt call.
reset_case
: >"$STUB_DIR/dpkg_installed"
run install
if [[ $RC -eq 0 ]] && [[ $OUT == *'skip: handy already installed'* ]] &&
	[[ ! -f $STUB_DIR/curl-calls ]] && [[ ! -f $STUB_DIR/apt-calls ]] &&
	[[ ! -f $STUB_DIR/minisign-calls ]]; then
	pass 'rerun skips an installed Handy without network or apt calls'
else
	fail "version guard (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 5. arm64 maps to the arm64 release asset.
reset_case
printf 'aarch64\n' >"$STUB_DIR/arch"
run install
if [[ $RC -eq 0 ]] && diff -u "$T/expected-arm64" <(curl_urls) >/dev/null &&
	apt_installs_deb && tmp_empty; then
	pass 'arm64 uses the arm64 release asset'
else
	fail "arm64 (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 6. Unknown architecture fails before any artifact reaches apt.
reset_case
printf 'riscv64\n' >"$STUB_DIR/arch"
run install
if [[ $RC -ne 0 ]] && ! apt_installs_deb && tmp_empty &&
	grep -q 'unsupported architecture' "$T/stderr"; then
	pass 'unsupported architecture fails closed'
else
	fail "unsupported arch (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 7. Sourcing the script performs no install side effects.
reset_case
env PATH="$T/bin:$T/sysbin" TMPDIR="$T/tmp" HOME="$T" STUB_DIR="$STUB_DIR" \
	STUB_RELEASE="$STUB_RELEASE" bash "$T/source-only.sh" "$SRC" >/dev/null 2>&1
source_rc=$?
if [[ $source_rc -eq 0 && ! -f $STUB_DIR/curl-calls && ! -f $STUB_DIR/apt-calls &&
	! -f $STUB_DIR/minisign-calls ]]; then
	pass 'sourcing the script writes nothing'
else
	fail "source-only (rc=$source_rc)"
fi

if ((FAILURES > 0)); then
	printf '%d test(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all handy verified-artifact tests passed\n'
