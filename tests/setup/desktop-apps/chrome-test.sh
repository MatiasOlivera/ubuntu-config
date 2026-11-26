#!/usr/bin/env bash
#
# chrome-test.sh — hermetic use-case tests for issue #84.
# Chrome moves from a raw vendor .deb to Google's signed apt repository. curl,
# gpg, sudo, tee, rm and apt are local stubs and all paths are sandboxed under
# FAKE_ROOT: no network, no real apt directories, no host changes. CHROME_SRC
# overrides the script under test.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${CHROME_SRC:-$ROOT/setup/desktop-apps/chrome.sh}"
FAILURES=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	printf 'ok: %s\n' "$1"
}

T="$(mktemp -d)" || {
	printf 'error: mktemp failed\n' >&2
	exit 1
}
REAL_RM="$(command -v rm)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/chrome-bin" "$T/sysbin" "$T/stubs" "$T/root"
STUB_DIR="$T/stubs"
FAKE_ROOT="$T/root"
export STUB_DIR FAKE_ROOT REAL_RM

# Closed set of real tools the script and stubs use. Everything that touches
# the network or the system is replaced by a stub in $T/bin.
for b in awk basename bash cat cmp cp dirname grep head mkdir mktemp sort tr wc; do
	ln -s "$(command -v "$b")" "$T/sysbin/$b"
done

cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
url=""
for arg in "$@"; do
	case $arg in https://*) url=$arg ;; esac
done
printf '%s\n' "$url" >> "$STUB_DIR/curl-calls"
[[ $url == https://dl.google.com/linux/linux_signing_key.pub ]] || exit 22
printf 'fixture armored key\n'
EOF

cat > "$T/bin/gpg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/gpg-calls"
out=""
while [[ $# -gt 0 ]]; do
	if [[ $1 == -o ]]; then
		out=$2
		shift 2
	else
		shift
	fi
done
[[ -n $out ]] || exit 2
target="$FAKE_ROOT$out"
mkdir -p "$(dirname "$target")"
printf 'fixture dearmored key bytes\n' > "$target"
EOF

cat > "$T/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/sudo-calls"
exec "$@"
EOF

cat > "$T/bin/tee" <<'EOF'
#!/usr/bin/env bash
path=""
for arg in "$@"; do
	[[ $arg == /* ]] && path=$arg
done
[[ -n $path ]] || exit 2
target="$FAKE_ROOT$path"
mkdir -p "$(dirname "$target")"
cat > "$target"
EOF

cat > "$T/bin/rm" <<'EOF'
#!/usr/bin/env bash
args=()
for arg in "$@"; do
	if [[ $arg == /* ]]; then
		args+=("$FAKE_ROOT$arg")
	else
		args+=("$arg")
	fi
done
"$REAL_RM" "${args[@]}"
EOF

cat > "$T/bin/apt" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/apt-calls"
exit 0
EOF

cat > "$T/chrome-bin/google-chrome" <<'EOF'
#!/usr/bin/env bash
printf 'Google Chrome 158.0.8127.88\n'
EOF

chmod +x "$T/bin/"* "$T/chrome-bin/"*

cat > "$T/source-only.sh" <<'EOF'
#!/usr/bin/env bash
source "$1"
EOF

CANON="$FAKE_ROOT/etc/apt/sources.list.d/google-chrome.sources"
LEGACY="$FAKE_ROOT/etc/apt/sources.list.d/google-chrome.list"
KEY="$FAKE_ROOT/usr/share/keyrings/google-chrome.gpg"

cat > "$T/expected" <<'EOF'
Types: deb
URIs: https://dl.google.com/linux/chrome-stable/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/google-chrome.gpg
EOF

reset_case() {
	"$REAL_RM" -rf "$FAKE_ROOT"
	mkdir -p "$FAKE_ROOT"
	"$REAL_RM" -f "$STUB_DIR/curl-calls" "$STUB_DIR/gpg-calls" \
		"$STUB_DIR/sudo-calls" "$STUB_DIR/apt-calls" "$STUB_DIR/first"
}

run() {
	local command=$1 with_chrome=$2 path
	OUT=""
	ERR=""
	RC=0
	if [[ $with_chrome == 1 ]]; then
		path="$T/chrome-bin:$T/bin:$T/sysbin"
	else
		path="$T/bin:$T/sysbin"
	fi
	if OUT="$(env PATH="$path" STUB_DIR="$STUB_DIR" FAKE_ROOT="$FAKE_ROOT" \
		REAL_RM="$REAL_RM" bash "$SRC" "$command" 2>"$T/stderr")"; then
		RC=0
	else
		RC=$?
	fi
	ERR="$(cat "$T/stderr")"
}

chrome_entries() {
	grep -rl 'dl.google.com/linux/chrome' \
		"$FAKE_ROOT/etc/apt/sources.list.d" 2>/dev/null | wc -l
}

signed_by_values() {
	grep -rhoE 'Signed-By: [^[:space:]]+|signed-by=[^[:space:]]+' \
		"$FAKE_ROOT/etc/apt/sources.list.d" 2>/dev/null | sort -u
}

canonical_ok() {
	[[ -f $CANON ]] && cmp -s "$T/expected" "$CANON" && [[ -f $KEY ]] &&
		[[ $(chrome_entries) -eq 1 ]] && [[ $(signed_by_values | wc -l) -eq 1 ]]
}

no_raw_deb() {
	[[ ! -f $STUB_DIR/curl-calls ]] || ! grep -q 'linux/direct' "$STUB_DIR/curl-calls"
}

write_vendor_source() {
	mkdir -p "$(dirname "$CANON")"
	cat > "$CANON" <<'EOF'
### THIS FILE IS AUTOMATICALLY CONFIGURED ###
Types: deb
URIs: https://dl.google.com/linux/chrome-stable/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/google-chrome.gpg
EOF
}

# 1. Fresh machine: canonical source from Google's key, no raw deb download.
reset_case
run repository 0
if [[ $RC -eq 0 ]] && canonical_ok &&
	grep -Fxq 'https://dl.google.com/linux/linux_signing_key.pub' "$STUB_DIR/curl-calls" &&
	grep -Fq -- '--dearmor --yes -o /usr/share/keyrings/google-chrome.gpg' "$STUB_DIR/gpg-calls"; then
	pass 'fresh run writes Google source and key'
else
	fail "fresh run (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 2. A legacy one-line source is pruned, leaving one canonical entry.
reset_case
mkdir -p "$(dirname "$LEGACY")"
printf 'deb [arch=amd64] https://dl.google.com/linux/chrome/deb/ stable main\n' > "$LEGACY"
run repository 0
if [[ $RC -eq 0 ]] && canonical_ok && [[ ! -e $LEGACY ]]; then
	pass 'legacy chrome.list is pruned'
else
	fail "legacy source (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 3. Rerun after the package postinst rewrote the source with its own header.
reset_case
run repository 0
write_vendor_source
run repository 0
if [[ $RC -eq 0 ]] && canonical_ok; then
	pass 'rerun after package rewrite converges'
else
	fail "package-rewritten rerun (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 4. Repeating the repository step leaves the canonical file unchanged.
reset_case
run repository 0
[[ -f $CANON ]] && cp "$CANON" "$STUB_DIR/first"
run repository 0
if [[ $RC -eq 0 ]] && cmp -s "$STUB_DIR/first" "$CANON"; then
	pass 'repository step is byte-for-byte idempotent'
else
	fail "idempotence (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 5. Sourcing the script writes nothing and other repositories stay untouched.
reset_case
mkdir -p "$(dirname "$CANON")"
printf 'sentinel\n' > "$FAKE_ROOT/etc/apt/sources.list.d/other.list"
env PATH="$T/bin:$T/sysbin" STUB_DIR="$STUB_DIR" FAKE_ROOT="$FAKE_ROOT" \
	REAL_RM="$REAL_RM" bash "$T/source-only.sh" "$SRC" >/dev/null 2>&1
source_rc=$?
if [[ $source_rc -eq 0 && ! -e $CANON && ! -e $KEY && ! -e $LEGACY ]] &&
	grep -Fxq 'sentinel' "$FAKE_ROOT/etc/apt/sources.list.d/other.list"; then
	pass 'sourcing the script writes nothing'
else
	fail "source-only (rc=$source_rc)"
fi

# 6. Install uses the apt package and the version guard skips reinstalls.
reset_case
run install 0
if [[ $RC -eq 0 ]] && grep -Fxq 'install -y google-chrome-stable' "$STUB_DIR/apt-calls" &&
	no_raw_deb; then
	pass 'install uses the vendor apt package'
else
	fail "apt install (rc=$RC out=[$OUT] err=[$ERR])"
fi
cp "$STUB_DIR/apt-calls" "$STUB_DIR/apt-first"
run install 1
if [[ $RC -eq 0 ]] && [[ $OUT == *'skip: chrome already installed'* ]] &&
	cmp -s "$STUB_DIR/apt-first" "$STUB_DIR/apt-calls" && no_raw_deb; then
	pass 'rerun skips an installed Chrome without calling apt'
else
	fail "version guard (rc=$RC out=[$OUT] err=[$ERR])"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d test(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all chrome apt source tests passed\n'
