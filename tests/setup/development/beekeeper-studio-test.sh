#!/usr/bin/env bash
#
# beekeeper-studio-test.sh — use-case tests for the Beekeeper apt repository
# step (issue #81). Black-box: drives the script's public `repository` command
# and asserts status, output and fixture files. Hermetic: stubbed curl/sudo/
# gpg/chmod/tee, no network, apt or system changes. The gpg stub reproduces
# the overwrite prompt that fails without a TTY. Fail-closed: any failure
# exits 1.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${BEEKEEPER_SRC:-$ROOT/setup/development/beekeeper-studio.sh}"
FAILURES=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	printf 'ok: %s\n' "$1"
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/stubs"
STUB_DIR="$T/stubs"
export STUB_DIR

# curl serves the fixture key; content is swapped between runs.
cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/curl-calls"
cat "$STUB_DIR/key-content"
EOF

# gpg mimics the no-TTY overwrite prompt: existing --output without --yes is
# a hard failure. Output paths are mapped into the fixture directory.
cat > "$T/bin/gpg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/gpg-calls"
out="" yes=0
while (( $# )); do
	case $1 in
	-o|--output) out=$2; shift 2 ;;
	--yes) yes=1; shift ;;
	*) shift ;;
	esac
done
[[ -n $out ]] || exit 2
target="$STUB_DIR/$(basename "$out")"
if [[ -e $target && $yes -eq 0 ]]; then
	printf "gpg: cannot open '/dev/tty': No such device or address\n" >&2
	exit 2
fi
cat > "$target"
EOF

# sudo runs the command locally; chmod is inert; tee captures the source line.
cat > "$T/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/sudo-calls"
exec "$@"
EOF
cat > "$T/bin/chmod" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/chmod-calls"
EOF
cat > "$T/bin/tee" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/tee-calls"
cat > "$STUB_DIR/sources.list"
EOF
chmod +x "$T/bin/"*

call() {
	PATH="$T/bin:$PATH" bash "$SRC" repository </dev/null
}

# Fresh run: key and source are written.
printf 'fixture-key-v1\n' > "$STUB_DIR/key-content"
out=$(call 2>&1); rc=$?
key=""
src=""
[[ -f $STUB_DIR/beekeeper.gpg ]] && key=$(<"$STUB_DIR/beekeeper.gpg")
[[ -f $STUB_DIR/sources.list ]] && src=$(<"$STUB_DIR/sources.list")
expected_src='deb [signed-by=/usr/share/keyrings/beekeeper.gpg] https://deb.beekeeperstudio.io stable main'
if [[ $rc -eq 0 && -f $STUB_DIR/beekeeper.gpg ]] &&
	[[ $key == fixture-key-v1 && $src == "$expected_src" ]]; then
	pass "fresh run writes key and source"
else
	fail "fresh run writes key and source (rc=$rc out=$out)"
fi

# Rerun with the key already present: must overwrite without a TTY prompt.
printf 'fixture-key-v2\n' > "$STUB_DIR/key-content"
out=$(call 2>&1); rc=$?
if [[ $rc -eq 0 && $(<"$STUB_DIR/beekeeper.gpg") == fixture-key-v2 && $out != *'/dev/tty'* ]]; then
	pass "rerun overwrites key without a TTY prompt"
else
	fail "rerun overwrites key without a TTY prompt (rc=$rc out=$out)"
fi

# The source file is overwritten, never appended.
if [[ $(wc -l < "$STUB_DIR/sources.list") -eq 1 && $(wc -l < "$STUB_DIR/tee-calls") -eq 2 ]]; then
	pass "rerun rewrites source without appending"
else
	fail "rerun rewrites source without appending (lines=$(wc -l < "$STUB_DIR/sources.list"))"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all beekeeper checks passed\n'
