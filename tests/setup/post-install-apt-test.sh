#!/usr/bin/env bash
# post-install-apt-test.sh — hermetic test for the pre-step apt failure path.
# sudo is stubbed and FAIL_FAST stops at the first failing step, so no install
# step runs. No network, no apt, no host changes.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/setup/post-install.sh"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/stubs" "$T/home"
STUB_DIR="$T/stubs"
export STUB_DIR

cat > "$T/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/sudo-calls"
[[ $* == *'apt update'* ]] && exit 7
exit 0
EOF
chmod +x "$T/bin/sudo"

RC=0
env PATH="$T/bin:$PATH" HOME="$T/home" FAIL_FAST=1 \
	bash "$SRC" >"$T/out" 2>"$T/err" || RC=$?

if [[ $RC -eq 7 ]]; then
	pass 'failed apt update exits with its status'
else
	fail "exit status (rc=$RC)"
fi
if grep -qF 'FAILED: apt_update (status 7)' "$T/err"; then
	pass 'failed apt update is named as a failed step'
else
	fail "no failed-step line (err=$(cat "$T/err"))"
fi
if grep -qF 'apt upgrade' "$STUB_DIR/sudo-calls"; then
	fail 'apt upgrade ran after the failed update'
else
	pass 'apt upgrade did not run after the failed update'
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all post-install apt tests passed\n'
