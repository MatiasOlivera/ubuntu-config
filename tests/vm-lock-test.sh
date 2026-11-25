#!/usr/bin/env bash
#
# vm-lock-test.sh — hermetic checks for tests/vm-lock.sh. No Multipass or network.

# Positional parameters in bash -c strings expand inside that shell, not here.
# shellcheck disable=SC2016

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/tests/vm-lock.sh"
FAILURES=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	printf 'ok: %s\n' "$1"
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/vm-lock-test.XXXXXX")"
holder=
trap 'rm -rf "$TMP"; [[ -n $holder ]] && kill "$holder" 2>/dev/null || true' EXIT
export TMPDIR="$TMP"
mkdir -p "$TMP/no-flock"

VM="one-run-per-vm-$$"
OTHER_VM="other-worktree-$$"

# 1. Sourcing the helper has no CLI side effects.
if out="$(bash -c 'source "$1"' _ "$SRC" 2>&1)" && [[ -z $out ]]; then
	pass "source has no side effects"
else
	fail "source has no side effects (out=$out)"
fi

# 2. A holder takes ownership and signals when it is ready.
ready="$TMP/ready"
release="$TMP/release"
bash -c '
	src=$1; vm=$2; ready=$3; release=$4
	source "$src" || exit 9
	vm_lock_acquire "$vm" || exit 8
	: > "$ready"
	for ((i = 0; i < 100; i++)); do
		[[ -e $release ]] && exit 0
		sleep 0.05
	done
	exit 7
' _ "$SRC" "$VM" "$ready" "$release" &
holder=$!

for ((i = 0; i < 100; i++)); do
	[[ -e $ready ]] && break
	sleep 0.05
done
if [[ -e $ready ]]; then
	pass "first run acquires the VM"
else
	fail "first run acquires the VM"
fi

# 3. A second run against the same VM is rejected with a VM-naming message.
if out="$(bash -c 'source "$1"; vm_lock_acquire "$2"' _ "$SRC" "$VM" 2>&1)"; then
	fail "second run is rejected (rc=0)"
elif [[ $out == *"$VM"* ]]; then
	pass "second run is rejected with a VM-naming message"
else
	fail "second run is rejected with a VM-naming message (out=$out)"
fi

# 4. A different VM is unaffected.
if bash -c 'source "$1"; vm_lock_acquire "$2"' _ "$SRC" "$OTHER_VM" >/dev/null 2>&1; then
	pass "a different VM can be acquired while one is held"
else
	fail "a different VM can be acquired while one is held"
fi

# 5. Without the locking facility, acquisition fails closed with a message.
if out="$(env PATH="$TMP/no-flock" /bin/bash -c 'source "$1"; vm_lock_acquire "$2"' _ "$SRC" "$VM" 2>&1)"; then
	fail "missing lock facility fails closed (rc=0)"
elif [[ $out == *flock* ]]; then
	pass "missing lock facility fails closed with a message"
else
	fail "missing lock facility fails closed with a message"
fi

# 6. Ownership ends when the holder exits, even without explicit release.
: > "$release"
wait "$holder"
holder_rc=$?
holder=
if [[ $holder_rc -eq 0 ]]; then
	pass "holder exits cleanly"
else
	fail "holder exits cleanly (rc=$holder_rc)"
fi

if bash -c 'source "$1"; vm_lock_acquire "$2"' _ "$SRC" "$VM" >/dev/null 2>&1; then
	pass "a later run can use the VM without manual cleanup"
else
	fail "a later run can use the VM without manual cleanup"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all vm-lock checks passed\n'
