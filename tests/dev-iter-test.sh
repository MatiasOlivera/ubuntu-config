#!/usr/bin/env bash
#
# dev-iter-test.sh — hermetic test for the development shortcut. Uses a temp
# git checkout and a stubbed Multipass; no VM, network or sudo is touched.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/tests/dev-iter.sh"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
REPO="$T/repo"
LOG="$T/multipass.log"

mkdir -p "$REPO/setup/development" "$T/state"
printf '#!/usr/bin/env bash\n' > "$REPO/setup/development/foo.sh"
printf '#!/usr/bin/env bash\n' > "$REPO/setup/development/baz.sh"
git -C "$REPO" init -q
git -C "$REPO" add setup
git -C "$REPO" -c user.name=Test -c user.email=test@example.com commit -qm init

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$MULTIPASS_LOG"\n' > "$T/multipass"
chmod +x "$T/multipass"

export UBUNTU_CONFIG_ROOT="$REPO" VM_NAME=stub-vm MULTIPASS="$T/multipass"
export MULTIPASS_LOG="$LOG" XDG_STATE_HOME="$T/state"

if bash "$HELPER" seed > "$T/seed.out" 2>&1; then
	[[ -s $T/state/ubuntu-workstation/dev-iter-stub-vm.sha ]] &&
		pass "seed: baseline recorded" || fail "seed: no baseline"
else
	printf 'seed output:\n' >&2
	cat "$T/seed.out" >&2
	fail "seed: failed"
fi

printf '#!/usr/bin/env bash\necho changed\n' > "$REPO/setup/development/foo.sh"
if bash "$HELPER" > "$T/run.out" 2>&1; then
	pass "iteration: status 0"
else
	printf 'iteration output:\n' >&2
	cat "$T/run.out" >&2
	fail "iteration: non-zero status"
fi

if grep -q 'foo.sh install' "$LOG"; then
	pass "iteration: changed script re-run"
else
	fail "iteration: changed script missing"
fi
if grep -q 'sudo apt update' "$LOG"; then
	pass "iteration: apt metadata refreshed"
else
	fail "iteration: apt update missing"
fi
if grep -q 'which git docker zsh curl' "$LOG"; then
	pass "iteration: smoke check present"
else
	fail "iteration: smoke check missing"
fi
if grep -q 'baz.sh' "$LOG"; then
	fail "iteration: unchanged script re-run"
else
	pass "iteration: unchanged script skipped"
fi

if bash "$HELPER" > "$T/second.out" 2>&1 && grep -q 'no changed setup scripts' "$T/second.out"; then
	pass "iteration: no-op after run"
else
	fail "iteration: expected no-op after run"
fi

[[ $FAILURES -eq 0 ]] || exit 1
