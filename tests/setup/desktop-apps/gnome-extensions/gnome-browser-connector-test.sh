#!/usr/bin/env bash
#
# gnome-browser-connector-test.sh — use-case tests for the browser connector
# installer. Black-box: only exit codes, stdout markers and apt-invocation
# logs. Hermetic: stubbed sudo/dpkg, no real apt. CONNECTOR_SRC overrides the
# script under test so the same suite runs against temporal mutants.
# Fail-closed: any failure exits 1.

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SRC="${CONNECTOR_SRC:-$ROOT/setup/desktop-apps/gnome-extensions/gnome-browser-connector.sh}"
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
mkdir -p "$T/bin"
STUB_DIR="$T/stubs"
mkdir -p "$STUB_DIR"
export STUB_DIR

# Stub sudo: always succeeds, logs invocations (proves apt runs iff needed).
cat > "$T/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/sudo-calls"
exit 0
EOF
# Stub dpkg: reports the connector present unless dpkg-missing exists.
cat > "$T/bin/dpkg" <<'EOF'
#!/usr/bin/env bash
[[ $1 == "-s" && $2 == "gnome-browser-connector" ]] || exit 1
[[ -f $STUB_DIR/dpkg-missing ]] && exit 1
printf 'Package: gnome-browser-connector\nVersion: 42.1-7\n'
EOF
chmod +x "$T/bin/"*

call() {
	PATH="$T/bin:$PATH" bash "$SRC" "$@" </dev/null
}

# U14. Version parses the dpkg record.
if [[ $(call version 2>&1) == "Version: 42.1-7" ]]; then
	pass "version parses dpkg record"
else
	fail "version parses dpkg record"
fi

# U13. Present package: install skips and never touches apt.
rm -f "$STUB_DIR/sudo-calls"
out=$(call install 2>&1); rc=$?
if [[ $rc -eq 0 && $out == *skip:* && ! -f $STUB_DIR/sudo-calls ]]; then
	pass "present package skips without apt"
else
	fail "present package skips without apt (rc=$rc out=$out)"
fi

# U12. Missing package: install runs apt exactly once and succeeds.
touch "$STUB_DIR/dpkg-missing"
rm -f "$STUB_DIR/sudo-calls"
out=$(call install 2>&1); rc=$?
rm -f "$STUB_DIR/dpkg-missing"
if [[ $rc -eq 0 && $(wc -l < "$STUB_DIR/sudo-calls") -eq 1 ]]; then
	pass "missing package installs via apt"
else
	fail "missing package installs via apt (rc=$rc out=$out)"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all connector checks passed\n'
