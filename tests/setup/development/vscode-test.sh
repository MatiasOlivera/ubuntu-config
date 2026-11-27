#!/usr/bin/env bash
#
# vscode-test.sh — hermetic use-case tests for issue #180. Black-box: drives
# the script's public `repository` command and asserts status, output and
# fixture files. curl/gpg/sudo/tee/rm are stubs; all writes stay under FAKE_ROOT
# and stdin is /dev/null so a real overwrite prompt cannot be answered. The gpg
# stub reproduces the no-TTY prompt failure (existing output without --yes).
# Fail-closed: any failure exits 1.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${VSCODE_SRC:-$ROOT/setup/development/vscode.sh}"
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

# Closed set of real tools the script and stubs use. Everything touching the
# network or the system is replaced by a stub in $T/bin.
for b in awk basename bash cat cmp cp dirname env grep head mkdir mktemp sort tr wc; do
	ln -s "$(command -v "$b")" "$T/sysbin/$b"
done

cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/curl-calls"
[[ $* == *'packages.microsoft.com/keys/microsoft.asc'* ]] || exit 22
cat "$STUB_DIR/key-content"
EOF

# gpg maps -o/--output into FAKE_ROOT. An existing output without --yes is a
# hard failure, mimicking gpg's overwrite prompt with no terminal.
cat > "$T/bin/gpg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/gpg-calls"
out="" yes=0
while (( $# )); do
	case $1 in
	-o | --output) out=$2; shift 2 ;;
	--yes) yes=1; shift ;;
	*) shift ;;
	esac
done
[[ -n $out ]] || exit 2
[[ ! -e $STUB_DIR/gpg-fail ]] || exit 2
target="$FAKE_ROOT$out"
if [[ -e $target && $yes -eq 0 ]]; then
	printf "gpg: cannot open '/dev/tty': No such device or address\n" >&2
	exit 2
fi
mkdir -p "$(dirname "$target")"
cat > "$target"
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

KEY="$FAKE_ROOT/usr/share/keyrings/microsoft.gpg"
SOURCE="$FAKE_ROOT/etc/apt/sources.list.d/vscode.sources"
SIBLING="$FAKE_ROOT/etc/apt/sources.list.d/vscode.list"
cat > "$T/expected" <<'EOF'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF

reset_case() {
	"$REAL_RM" -rf "$FAKE_ROOT"
	mkdir -p "$FAKE_ROOT"
	"$REAL_RM" -f "$STUB_DIR/curl-calls" "$STUB_DIR/gpg-calls" \
		"$STUB_DIR/sudo-calls" "$STUB_DIR/gpg-fail" "$STUB_DIR/first"
}

run() {
	OUT=""
	ERR=""
	RC=0
	if OUT="$(env PATH="$T/bin:$T/sysbin" STUB_DIR="$STUB_DIR" FAKE_ROOT="$FAKE_ROOT" \
		REAL_RM="$REAL_RM" bash "$SRC" repository </dev/null 2>"$T/stderr")"; then
		RC=0
	else
		RC=$?
	fi
	ERR="$(cat "$T/stderr")"
}

# 1. Fresh run: key and canonical source are written, gpg is non-interactive.
reset_case
printf 'fixture-key-v1\n' > "$STUB_DIR/key-content"
run
if [[ $RC -eq 0 && -f $KEY && -f $SOURCE ]] &&
	cmp -s "$T/expected" "$SOURCE" &&
	grep -Fq -- '--dearmor --yes -o /usr/share/keyrings/microsoft.gpg' "$STUB_DIR/gpg-calls"; then
	pass 'fresh run writes key and canonical source'
else
	fail "fresh run (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 2. Rerun over an existing key: overwrite without a TTY prompt, source unchanged.
cp "$SOURCE" "$STUB_DIR/first" 2>/dev/null || true
printf 'fixture-key-v2\n' > "$STUB_DIR/key-content"
run
if [[ $RC -eq 0 && $(<"$KEY") == fixture-key-v2 ]] &&
	[[ $ERR != *'/dev/tty'* ]] && cmp -s "$STUB_DIR/first" "$SOURCE"; then
	pass 'rerun overwrites key without a TTY prompt'
else
	fail "rerun (rc=$RC out=[$OUT] err=[$ERR])"
fi

# 3. Key that cannot be written fails the step; the source is not rewritten.
reset_case
printf 'fixture-key-v1\n' > "$STUB_DIR/key-content"
: > "$STUB_DIR/gpg-fail"
run
if [[ $RC -ne 0 && ! -e $SOURCE ]]; then
	pass 'unwritable key fails the step before writing the source'
else
	fail "unwritable key (rc=$RC out=[$OUT] err=[$ERR] source=$([[ -e $SOURCE ]] && echo present || echo absent))"
fi

# 4. Sourcing the script writes nothing.
reset_case
env PATH="$T/bin:$T/sysbin" STUB_DIR="$STUB_DIR" FAKE_ROOT="$FAKE_ROOT" \
	REAL_RM="$REAL_RM" bash "$T/source-only.sh" "$SRC" >/dev/null 2>&1
source_rc=$?
if [[ $source_rc -eq 0 && ! -e $KEY && ! -e $SOURCE && ! -e $SIBLING ]]; then
	pass 'sourcing the script writes nothing'
else
	fail "source-only (rc=$source_rc)"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d test(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all vscode repository checks passed\n'
