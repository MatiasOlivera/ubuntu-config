#!/usr/bin/env bash
#
# cursor-test.sh — hermetic use-case tests for issue #80.
# The Cursor .deb postinst registers the same apt source with a different
# Signed-By; a rerun must leave one canonical entry. curl, gpg, sudo, tee and rm
# are local stubs and all paths are sandboxed under FAKE_ROOT: no network, no
# real apt directories, no host changes. CURSOR_SRC overrides the script.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${CURSOR_SRC:-$ROOT/setup/development/cursor.sh}"
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
mkdir -p "$T/bin" "$T/sysbin" "$T/stubs" "$T/root"
STUB_DIR="$T/stubs"
FAKE_ROOT="$T/root"
export STUB_DIR FAKE_ROOT

# Closed set of real tools the script and stubs use. Everything else that
# touches the network or the system is replaced by a stub in $T/bin.
for b in awk basename bash cat cmp dirname find grep head mkdir mktemp sort tr wc; do
	ln -s "$(command -v "$b")" "$T/sysbin/$b"
done

cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
url=""
for arg in "$@"; do
	case $arg in https://*) url=$arg ;; esac
done
printf '%s\n' "$url" >> "$STUB_DIR/curl-calls"
[[ $url == https://downloads.cursor.com/keys/anysphere.asc ]] || exit 22
printf 'fixture armored key\n'
EOF

cat > "$T/bin/gpg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/gpg-calls"
printf 'fixture dearmored key bytes\n'
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

chmod +x "$T/bin/"*

cat > "$T/source-only.sh" <<'EOF'
#!/usr/bin/env bash
source "$1"
EOF

CANON="$FAKE_ROOT/etc/apt/sources.list.d/cursor.sources"
LEGACY="$FAKE_ROOT/etc/apt/sources.list.d/cursor.list"
KEY="$FAKE_ROOT/usr/share/keyrings/anysphere.gpg"
OLD_KEY="$FAKE_ROOT/etc/apt/keyrings/cursor.gpg"

reset_case() {
	"$REAL_RM" -rf "$FAKE_ROOT"
	mkdir -p "$FAKE_ROOT"
	"$REAL_RM" -f "$STUB_DIR/curl-calls" "$STUB_DIR/gpg-calls" \
		"$STUB_DIR/sudo-calls" "$STUB_DIR/first"
}

run_repo() {
	OUT=""
	ERR=""
	RC=0
	if OUT="$(env PATH="$T/bin:$T/sysbin" \
		STUB_DIR="$STUB_DIR" FAKE_ROOT="$FAKE_ROOT" REAL_RM="$REAL_RM" \
		bash "$SRC" repository 2>"$T/stderr")"; then
		RC=0
	else
		RC=$?
	fi
	ERR="$(cat "$T/stderr")"
}

# apt's conflicting-Signed-By error means more than one distinct value across
# source files for the same URI, so that is the invariant the tests assert.
cursor_entries() {
	grep -rl 'downloads.cursor.com/aptrepo' \
		"$FAKE_ROOT/etc/apt/sources.list.d" 2>/dev/null | wc -l
}

signed_by_values() {
	grep -rhoE 'Signed-By: [^[:space:]]+|signed-by=[^[:space:]]+' \
		"$FAKE_ROOT/etc/apt/sources.list.d" 2>/dev/null | sort -u
}

canonical_ok() {
	[[ -f $CANON ]] &&
		grep -Fxq 'Types: deb' "$CANON" &&
		grep -Fxq 'URIs: https://downloads.cursor.com/aptrepo' "$CANON" &&
		grep -Fxq 'Suites: stable' "$CANON" &&
		grep -Fxq 'Components: main' "$CANON" &&
		grep -Fxq 'Architectures: amd64,arm64' "$CANON" &&
		grep -Fxq 'Signed-By: /usr/share/keyrings/anysphere.gpg' "$CANON"
}

converged() {
	canonical_ok && [[ ! -e $LEGACY && ! -e $OLD_KEY && -f $KEY ]] &&
		[[ $(cursor_entries) -eq 1 ]] && [[ $(signed_by_values | wc -l) -eq 1 ]]
}

write_vendor_source() {
	mkdir -p "$(dirname "$CANON")"
	cat > "$CANON" <<'EOF'
### THIS FILE IS AUTOMATICALLY CONFIGURED ###
Types: deb
URIs: https://downloads.cursor.com/aptrepo
Suites: stable
Components: main
Architectures: amd64,arm64
Signed-By: /usr/share/keyrings/anysphere.gpg
EOF
}

# 1. Fresh machine: one canonical source and the vendor key.
reset_case
run_repo
if [[ $RC -eq 0 ]] && converged &&
	grep -Fxq 'https://downloads.cursor.com/keys/anysphere.asc' "$STUB_DIR/curl-calls"; then
	pass 'fresh run writes one canonical Cursor source with the vendor key'
else
	fail "fresh run (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 2. Rerun after the .deb postinst rewrote the source with its own header.
reset_case
run_repo
write_vendor_source
run_repo
if [[ $RC -eq 0 ]] && converged; then
	pass 'rerun after the package rewrote the source converges'
else
	fail "package-rewritten rerun (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 3. Rerun from the two-conflicting-entries state left by the old script.
reset_case
mkdir -p "$(dirname "$CANON")" "$(dirname "$OLD_KEY")"
printf 'old key bytes\n' > "$OLD_KEY"
printf '%s\n' 'deb [arch=amd64,arm64 signed-by=/etc/apt/keyrings/cursor.gpg] https://downloads.cursor.com/aptrepo stable main' > "$LEGACY"
write_vendor_source
run_repo
if [[ $RC -eq 0 ]] && converged; then
	pass 'rerun from the conflicting state removes the stale entry and key'
else
	fail "conflicting-state rerun (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 4. Repeating the repository step leaves the canonical file unchanged.
reset_case
run_repo
[[ -f $CANON ]] && cp "$CANON" "$STUB_DIR/first"
run_repo
if [[ $RC -eq 0 ]] && [[ -f $CANON ]] && cmp -s "$STUB_DIR/first" "$CANON"; then
	pass 'repository step is byte-for-byte idempotent'
else
	fail "idempotence (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 5. Sourcing has no side effects and other repositories are untouched.
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
run_repo
if [[ $RC -eq 0 ]] && grep -Fxq 'sentinel' "$FAKE_ROOT/etc/apt/sources.list.d/other.list" &&
	[[ $(cursor_entries) -eq 1 ]]; then
	pass 'other apt sources stay unchanged'
else
	fail "other sources (rc=$RC out=[$OUT] err=[$ERR])"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d test(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all cursor apt source tests passed\n'
