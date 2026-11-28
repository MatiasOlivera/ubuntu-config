#!/usr/bin/env bash
#
# vm-name-test.sh — black-box checks for tests/vm-name.sh. Hermetic.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/tests/vm-name.sh"
FAILURES=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	printf 'ok: %s\n' "$1"
}

a="$(bash "$SRC" /tmp/agent-a/ubuntu-workstation)"
b="$(bash "$SRC" /tmp/agent-b/ubuntu-workstation)"
a_again="$(bash "$SRC" /tmp/agent-a/ubuntu-workstation)"
name_re='^ubuntu-workstation-test-[a-z0-9]([a-z0-9-]*[a-z0-9])?-[0-9A-Za-z]+$'

if [[ $a != "$b" ]]; then
	pass "different worktrees get different VMs"
else
	fail "different worktrees get different VMs (both $a)"
fi

if [[ $a == "$a_again" ]]; then
	pass "same worktree gets the same VM"
else
	fail "same worktree gets the same VM ($a vs $a_again)"
fi

if [[ $a =~ $name_re ]]; then
	pass "name is recognizable and Multipass-safe"
else
	fail "name is recognizable and Multipass-safe ($a)"
fi

if [[ $a == ubuntu-workstation-test-ubuntu-workstation-* ]]; then
	pass "checkout directory appears as a readable slug"
else
	fail "checkout directory appears as a readable slug ($a)"
fi

suffix="${a##*-}"
if [[ $suffix =~ ^[0-9A-Za-z]{1,9}$ ]]; then
	pass "digest suffix is base62 and compact"
else
	fail "digest suffix is base62 and compact ($suffix)"
fi

# The original repository (not a worktree) gets its own stable name too.
original="$(bash "$SRC" /home/user/ubuntu-workstation)"
if [[ $original == ubuntu-workstation-test-ubuntu-workstation-* && $original != "$a" ]]; then
	pass "original repository gets its own VM"
else
	fail "original repository gets its own VM ($original)"
fi

weird="$(bash "$SRC" '/tmp/Agent A/work tree_v1')"
if [[ $weird =~ $name_re && $weird == ubuntu-workstation-test-work-tree-v1-* ]]; then
	pass "odd path characters yield a safe, readable name"
else
	fail "odd path characters yield a safe, readable name ($weird)"
fi

long="$(bash "$SRC" '/tmp/this-is-a-very-long-worktree-directory-name')"
if (( ${#long} <= 59 )); then
	pass "slug length is bounded"
else
	fail "slug length is bounded (${#long} chars: $long)"
fi

if [[ $(bash "$SRC") == "$(bash "$SRC" "$PWD")" ]]; then
	pass "default path is the current directory"
else
	fail "default path is the current directory"
fi

# base62() unit checks (source-only: no CLI side effects).
# shellcheck source=tests/vm-name.sh
source "$SRC"

if [[ $(base62 0) == 0 && $(base62 9) == 9 && $(base62 10) == a &&
	$(base62 35) == z && $(base62 36) == A && $(base62 61) == Z ]]; then
	pass "base62 single-digit boundaries"
else
	fail "base62 single-digit boundaries"
fi

if [[ $(base62 62) == 10 && $(base62 63) == 11 && $(base62 3844) == 100 ]]; then
	pass "base62 multi-digit rollover"
else
	fail "base62 multi-digit rollover"
fi

if [[ $(base62 44928170029951) == cKZ6KOET ]]; then
	pass "base62 large value matches known conversion"
else
	fail "base62 large value ($(base62 44928170029951))"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all vm-name checks passed\n'
