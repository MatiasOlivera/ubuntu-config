#!/usr/bin/env bash
#
# orca-test.sh — hermetic use-case tests for issue #89.
# Orca moves from a raw vendor .deb to a checksum-verified release artifact.
# curl, sudo, apt and dpkg are stubs; the real sha256sum checks a tiny fixture.
# No network, no host changes. ORCA_SRC overrides the script under test.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
ORIG_SRC="${ORCA_SRC:-$ROOT/setup/desktop-apps/orca.sh}"
FAILURES=0
VERSION="1.4.206"
ASSET="orca-ide_${VERSION}_amd64.deb"
# Provenance: gh api repos/stablyai/orca/releases/tags/v1.4.206 — the digest
# GitHub publishes for this exact asset (the maintainer ships none for .deb).
UPSTREAM_SHA256="66e6ea0ca2aaeb706297d27bf7d6ecb8c352737954e4d527c6a66e0b1518b956"

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
REAL_RM="$(command -v rm)"
trap '"$REAL_RM" -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/sysbin" "$T/stubs" "$T/release" "$T/tmp"
STUB_DIR="$T/stubs"
STUB_RELEASE="$T/release"
export STUB_DIR STUB_RELEASE REAL_RM

# Closed set of real tools the script and stubs use.
for b in awk bash basename cat cmp cp diff dirname env find grep head mkdir mktemp mv rm sha256sum sort tr; do
	ln -s "$(command -v "$b")" "$T/sysbin/$b"
done

printf 'fixture orca deb bytes\n' >"$STUB_RELEASE/$ASSET"
GOOD_SHA="$(sha256sum "$STUB_RELEASE/$ASSET" | cut -d' ' -f1)"

# The script pins the real upstream digest; point a test copy at the fixture's
# digest so the real sha256sum can decide which bytes are installable. Keep the
# copy beside a dispatcher copy so its relative source line still resolves.
mkdir -p "$T/setup/desktop-apps" "$T/setup/helpers"
cp "$ROOT/setup/helpers/dispatcher.sh" "$T/setup/helpers/dispatcher.sh"
SRC="$T/setup/desktop-apps/orca.sh"
sed "s|^ORCA_SHA256=.*|ORCA_SHA256=\"$GOOD_SHA\"|" "$ORIG_SRC" >"$SRC"

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
if [[ -f $STUB_DIR/tamper ]]; then
	printf 'tampered bytes\n' >"$dest"
else
	cp "$STUB_RELEASE/${url##*/}" "$dest"
fi
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
[[ -f $STUB_DIR/dpkg_installed ]] && printf 'Version: 1.4.206\n'
exit 0
EOF

chmod +x "$T/bin/"*

cat >"$T/source-only.sh" <<'EOF'
#!/usr/bin/env bash
source "$1"
EOF

# Compare the URL only; the destination is a per-case mktemp path.
URL="https://github.com/stablyai/orca/releases/download/v${VERSION}/${ASSET}"

reset_case() {
	"$REAL_RM" -rf "$T/tmp"
	mkdir -p "$T/tmp"
	"$REAL_RM" -f "$STUB_DIR/curl-calls" "$STUB_DIR/sudo-calls" \
		"$STUB_DIR/apt-calls" "$STUB_DIR/dpkg-calls" \
		"$STUB_DIR/curl_fail" "$STUB_DIR/tamper" "$STUB_DIR/dpkg_installed"
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

apt_installs_deb() {
	grep -qE "^install -y /.*${ASSET//./\\.}$" "$STUB_DIR/apt-calls" 2>/dev/null
}

tmp_empty() {
	[[ -z $(find "$T/tmp" -mindepth 1 -print -quit 2>/dev/null) ]]
}

# 1. Fresh install: pinned artifact, verified with real sha256sum, then apt.
reset_case
run install
if [[ $RC -eq 0 ]] && grep -Fq "$URL " "$STUB_DIR/curl-calls" &&
	apt_installs_deb && grep -Fq "install -y $T/tmp" "$STUB_DIR/apt-calls" &&
	tmp_empty; then
	pass 'fresh install downloads the pinned asset, verifies, then installs it'
else
	fail "fresh install (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 2. Tampered bytes: checksum fails closed; nothing reaches apt.
reset_case
: >"$STUB_DIR/tamper"
run install
if [[ $RC -ne 0 ]] && ! apt_installs_deb && tmp_empty &&
	grep -q 'checksum mismatch' "$T/stderr"; then
	pass 'checksum mismatch fails closed without installing the deb'
else
	fail "tampered artifact (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 3. Download failure: no verification, no apt, no leftovers.
reset_case
: >"$STUB_DIR/curl_fail"
run install
if [[ $RC -ne 0 ]] && ! apt_installs_deb && tmp_empty &&
	grep -q 'cannot download' "$T/stderr"; then
	pass 'download failure fails closed'
else
	fail "download failure (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 4. Installed Orca: version guard skips before any network or apt call.
reset_case
: >"$STUB_DIR/dpkg_installed"
run install
if [[ $RC -eq 0 ]] && [[ $OUT == *"skip: orca already installed"* ]] &&
	[[ ! -f $STUB_DIR/curl-calls ]] && [[ ! -f $STUB_DIR/apt-calls ]]; then
	pass 'rerun skips an installed Orca without network or apt calls'
else
	fail "version guard (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 5. Sourcing the real script performs no install side effects.
reset_case
env PATH="$T/bin:$T/sysbin" TMPDIR="$T/tmp" HOME="$T" STUB_DIR="$STUB_DIR" \
	STUB_RELEASE="$STUB_RELEASE" bash "$T/source-only.sh" "$ORIG_SRC" \
	>/dev/null 2>&1
source_rc=$?
if [[ $source_rc -eq 0 && ! -f $STUB_DIR/curl-calls && ! -f $STUB_DIR/apt-calls ]]; then
	pass 'sourcing the script writes nothing'
else
	fail "source-only (rc=$source_rc)"
fi

# 6. The real script pins GitHub's published digest, not a local fixture.
if grep -Fq "ORCA_SHA256=\"$UPSTREAM_SHA256\"" "$ORIG_SRC"; then
	pass 'pinned digest matches the GitHub release-asset digest'
else
	fail 'pinned digest does not match the GitHub release-asset digest'
fi

if ((FAILURES > 0)); then
	printf '%d test(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all orca verified-artifact tests passed\n'
