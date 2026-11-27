#!/usr/bin/env bash
#
# apt-source-test.sh — hermetic tests for the shared apt source writer (issue #100).
# sudo, tee and rm are stubs and every path is sandboxed under FAKE_ROOT: no
# network, no real apt directories, no host changes. APT_SOURCE_SRC overrides
# the helper under test.
# shellcheck disable=SC2016 # the bash -c snippets are intentionally literal

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${APT_SOURCE_SRC:-$ROOT/setup/helpers/apt-source.sh}"
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
export STUB_DIR FAKE_ROOT REAL_RM

# Closed set of real tools the helper and stubs use.
for b in awk bash cat cmp cp dirname grep mkdir mktemp sort wc; do
	ln -s "$(command -v "$b")" "$T/sysbin/$b"
done

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
[[ ${TEE_FAIL:-0} != 1 ]] || exit 3
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
printf '%s\n' "${args[*]}" >> "$STUB_DIR/rm-calls"
"$REAL_RM" "${args[@]}"
EOF

chmod +x "$T/bin/"*

DEB822=$(cat <<'EOF'
Types: deb
URIs: https://example.test/aptrepo
Suites: stable
Components: main
Architectures: amd64,arm64
Signed-By: /usr/share/keyrings/vendor.gpg
EOF
)
ONELINE='deb [signed-by=/usr/share/keyrings/vendor.gpg] https://example.test/aptrepo stable main'

CANON="$FAKE_ROOT/etc/apt/sources.list.d/vendor.sources"
SIBLING="$FAKE_ROOT/etc/apt/sources.list.d/vendor.list"
STALE_KEY="$FAKE_ROOT/etc/apt/keyrings/old-vendor.gpg"
CONTENT=

run_write() {
	local args=("$@")
	RC=0
	if printf '%s\n' "$CONTENT" | env PATH="$T/bin:$T/sysbin" \
		STUB_DIR="$STUB_DIR" FAKE_ROOT="$FAKE_ROOT" REAL_RM="$REAL_RM" \
		TEE_FAIL="${TEE_FAIL:-0}" \
		bash -c 'source "$1"; shift; apt_source_write "$@"' bash "$SRC" "${args[@]}" \
		>"$T/stdout" 2>"$T/stderr"; then
		RC=0
	else
		RC=$?
	fi
	ERR="$(cat "$T/stderr")"
}

reset_case() {
	"$REAL_RM" -rf "$FAKE_ROOT"
	mkdir -p "$FAKE_ROOT"
	"$REAL_RM" -f "$STUB_DIR/sudo-calls" "$STUB_DIR/rm-calls"
}

# apt's conflicting-Signed-By error means more than one distinct value across
# source files for the same URI, so that is the invariant asserted here.
source_entries() {
	grep -rl 'example.test/aptrepo' \
		"$FAKE_ROOT/etc/apt/sources.list.d" 2>/dev/null | wc -l
}

signed_by_values() {
	grep -rhoE 'Signed-By: [^[:space:]]+|signed-by=[^[:space:]]+' \
		"$FAKE_ROOT/etc/apt/sources.list.d" 2>/dev/null | sort -u
}

# 1. Fresh write: one canonical source with the supplied bytes.
reset_case
CONTENT=$DEB822
run_write vendor.sources
if [[ $RC -eq 0 && -f $CANON ]] && cmp -s <(printf '%s\n' "$CONTENT") "$CANON"; then
	pass 'fresh write creates one canonical source'
else
	fail "fresh write (rc=$RC err=[$ERR])"
fi

# 2. A vendor rewrote the canonical source with its own Signed-By and left a
#    stale one-line variant and key: rerunning must converge to one Signed-By.
reset_case
mkdir -p "$(dirname "$CANON")" "$(dirname "$STALE_KEY")"
cat > "$CANON" <<'EOF'
### THIS FILE IS AUTOMATICALLY CONFIGURED ###
Types: deb
URIs: https://example.test/aptrepo
Suites: stable
Components: main
Architectures: amd64,arm64
Signed-By: /etc/apt/keyrings/old-vendor.gpg
EOF
printf 'deb [signed-by=/etc/apt/keyrings/older.gpg] https://example.test/aptrepo stable main\n' > "$SIBLING"
printf 'old key bytes\n' > "$STALE_KEY"
CONTENT=$DEB822
run_write vendor.sources /etc/apt/keyrings/old-vendor.gpg
if [[ $RC -eq 0 && -f $CANON && ! -e $SIBLING && ! -e $STALE_KEY ]] &&
	cmp -s <(printf '%s\n' "$CONTENT") "$CANON" &&
	[[ $(source_entries) -eq 1 ]] && [[ $(signed_by_values | wc -l) -eq 1 ]]; then
	pass 'rerun over a package-rewritten source converges to one Signed-By'
else
	fail "package-rewritten rerun (rc=$RC err=[$ERR])"
fi

# 3. Repeating the write leaves the canonical file byte-for-byte identical.
reset_case
CONTENT=$DEB822
run_write vendor.sources
cp "$CANON" "$STUB_DIR/first"
run_write vendor.sources
if [[ $RC -eq 0 ]] && cmp -s "$STUB_DIR/first" "$CANON"; then
	pass 'repeat write is byte-for-byte idempotent'
else
	fail "idempotence (rc=$RC err=[$ERR])"
fi

# 4. One-line sources work too, and prune the stale DEB822 sibling.
reset_case
mkdir -p "$(dirname "$CANON")"
printf 'stale\n' > "$CANON"
CONTENT=$ONELINE
run_write vendor.list
if [[ $RC -eq 0 && -f $SIBLING && ! -e $CANON ]] &&
	cmp -s <(printf '%s\n' "$CONTENT") "$SIBLING" &&
	[[ $(source_entries) -eq 1 ]] && [[ $(signed_by_values | wc -l) -eq 1 ]]; then
	pass 'one-line source prunes the stale DEB822 sibling'
else
	fail "one-line source (rc=$RC err=[$ERR])"
fi

# 5. Sourcing writes nothing and other repositories stay untouched.
reset_case
mkdir -p "$FAKE_ROOT/etc/apt/sources.list.d"
printf 'sentinel\n' > "$FAKE_ROOT/etc/apt/sources.list.d/other.list"
env PATH="$T/bin:$T/sysbin" STUB_DIR="$STUB_DIR" FAKE_ROOT="$FAKE_ROOT" \
	REAL_RM="$REAL_RM" bash -c 'source "$1"' bash "$SRC" >/dev/null 2>&1
source_rc=$?
if [[ $source_rc -eq 0 && ! -e $CANON && ! -e $SIBLING ]] &&
	grep -Fxq 'sentinel' "$FAKE_ROOT/etc/apt/sources.list.d/other.list"; then
	pass 'sourcing the helper writes nothing'
else
	fail "source-only (rc=$source_rc)"
fi
CONTENT=$DEB822
run_write vendor.sources
if [[ $RC -eq 0 ]] && grep -Fxq 'sentinel' "$FAKE_ROOT/etc/apt/sources.list.d/other.list" &&
	[[ $(source_entries) -eq 1 ]]; then
	pass 'other apt sources stay unchanged'
else
	fail "other sources (rc=$RC err=[$ERR])"
fi

# 6. A failed write fails the step and never prunes an existing source.
reset_case
mkdir -p "$(dirname "$CANON")" "$(dirname "$SIBLING")"
printf 'keep me\n' > "$SIBLING"
CONTENT=$DEB822
TEE_FAIL=1
run_write vendor.sources
TEE_FAIL=0
if [[ $RC -eq 3 && ! -e $CANON ]] && grep -Fxq 'keep me' "$SIBLING" &&
	[[ ! -s $STUB_DIR/rm-calls ]]; then
	pass 'failed write fails the step and leaves existing sources intact'
else
	fail "failed write (rc=$RC err=[$ERR])"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d test(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all apt source helper tests passed\n'
