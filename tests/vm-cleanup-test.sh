#!/usr/bin/env bash
#
# vm-cleanup-test.sh — hermetic checks for the Orca archive hook.
# multipass and notify-send are stubbed; no VM, notification or network.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/scripts/cleanup-worktree-vm.sh"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

if [[ ! -f $SRC ]]; then
	printf 'FAIL: %s missing (red state: no archive hook script)\n' "$SRC" >&2
	exit 1
fi

T="$(mktemp -d "${TMPDIR:-/tmp}/vm-cleanup-test.XXXXXX")" || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stubs" "$T/worktree/tests" "$T/outside" "$T/xdg"
git init -q "$T/worktree"
cp "$ROOT/tests/vm-name.sh" "$T/worktree/tests/vm-name.sh"

cat > "$T/stubs/multipass" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/multipass-calls"
case "$1" in
list)
	[[ ${STUB_LIST_RC:-0} -ne 0 ]] && exit "$STUB_LIST_RC"
	printf 'Name State IPv4 Image\n'
	[[ -n ${STUB_VM:-} ]] && printf '%s Running 127.0.0.1 Ubuntu\n' "$STUB_VM"
	printf 'other-worktree Running 127.0.0.1 Ubuntu\n'
	;;
delete) exit "${STUB_DELETE_RC:-0}" ;;
esac
exit 0
EOF
cat > "$T/stubs/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/notify-calls"
exit 0
EOF
chmod +x "$T/stubs/multipass" "$T/stubs/notify-send"

export STUB_DIR="$T/stubs"
export XDG_STATE_HOME="$T/xdg"
export PATH="$STUB_DIR:$PATH"

VM="$(bash "$ROOT/tests/vm-name.sh" "$T/worktree")"
OTHER="other-worktree"
LOG="$XDG_STATE_HOME/ubuntu-workstation/vm-cleanup-failures.log"

run_hook() {
	local out=$1
	shift
	env "$@" bash "$SRC" > "$out" 2> "$out.err"
}

# 1. Success: the VM named by tests/vm-name.sh is purged, nothing else is.
: > "$STUB_DIR/multipass-calls"
if run_hook "$T/success.out" ORCA_WORKTREE_PATH="$T/worktree" STUB_VM="$VM"; then
	pass "success: hook exits 0"
else
	fail "success: hook exits 0"
fi
if grep -qF "delete -p $VM" "$STUB_DIR/multipass-calls"; then
	pass "success: deletes the worktree's VM"
else
	fail "success: deletes the worktree's VM ($(cat "$STUB_DIR/multipass-calls"))"
fi
if grep -qF "$OTHER" "$STUB_DIR/multipass-calls"; then
	fail "success: other worktrees' VMs untouched"
else
	pass "success: other worktrees' VMs untouched"
fi
if grep -qF "$VM" "$T/success.out"; then
	pass "success: output names the VM"
else
	fail "success: output names the VM"
fi
if [[ -f $LOG ]]; then
	fail "success: no failure report written"
else
	pass "success: no failure report written"
fi

# 2. No VM for this checkout: no-op, no spurious report.
: > "$STUB_DIR/multipass-calls"
if run_hook "$T/absent.out" ORCA_WORKTREE_PATH="$T/worktree"; then
	pass "absent VM: hook exits 0"
else
	fail "absent VM: hook exits 0"
fi
if grep -q '^delete' "$STUB_DIR/multipass-calls"; then
	fail "absent VM: no delete attempted"
else
	pass "absent VM: no delete attempted"
fi

# 3. Failed delete: deletion of the workspace must still proceed, and the
# leftover VM must be reported visibly and durably.
: > "$STUB_DIR/multipass-calls"
if run_hook "$T/failed.out" ORCA_WORKTREE_PATH="$T/worktree" STUB_VM="$VM" STUB_DELETE_RC=7; then
	pass "failed delete: hook exits 0 so workspace deletion completes"
else
	fail "failed delete: hook exits 0 so workspace deletion completes"
fi
if grep -qF "$VM" "$T/failed.out.err"; then
	pass "failed delete: warning names the VM"
else
	fail "failed delete: warning names the VM"
fi
if grep -qF "$VM" "$LOG" 2>/dev/null; then
	pass "failed delete: leftover VM written to report"
else
	fail "failed delete: leftover VM written to report"
fi
if grep -qF "$VM" "$STUB_DIR/notify-calls" 2>/dev/null; then
	pass "failed delete: desktop notification names the VM"
else
	fail "failed delete: desktop notification names the VM"
fi

# 4. An unavailable Multipass daemon is reported, not mistaken for a missing VM.
: > "$STUB_DIR/multipass-calls"
rm -f "$LOG"
if run_hook "$T/list-failed.out" ORCA_WORKTREE_PATH="$T/worktree" STUB_VM="$VM" STUB_LIST_RC=5; then
	pass "list failure: hook exits 0"
else
	fail "list failure: hook exits 0"
fi
if grep -qF "$VM" "$T/list-failed.out.err" && grep -qF "$VM" "$LOG" 2>/dev/null; then
	pass "list failure: leftover VM reported"
else
	fail "list failure: leftover VM reported"
fi
if grep -q '^delete' "$STUB_DIR/multipass-calls"; then
	fail "list failure: no delete attempted"
else
	pass "list failure: no delete attempted"
fi

# 5. The hook's working directory identifies the worktree when Orca provides
# no path variable.
: > "$STUB_DIR/multipass-calls"
if (cd "$T/worktree" && env -u ORCA_WORKTREE_PATH STUB_VM="$VM" bash "$SRC") >/dev/null 2>&1; then
	pass "no path variable: current directory identifies the worktree"
else
	fail "no path variable: current directory identifies the worktree"
fi
if grep -qF "delete -p $VM" "$STUB_DIR/multipass-calls"; then
	pass "no path variable: same VM is targeted"
else
	fail "no path variable: same VM is targeted"
fi

# 6. An ambiguous path must not guess a VM.
: > "$STUB_DIR/multipass-calls"
if run_hook "$T/ambiguous.out" ORCA_WORKTREE_PATH="$T/outside" STUB_VM="$VM"; then
	pass "ambiguous worktree: hook exits 0"
else
	fail "ambiguous worktree: hook exits 0"
fi
if grep -q '^delete' "$STUB_DIR/multipass-calls"; then
	fail "ambiguous worktree: no delete attempted"
else
	pass "ambiguous worktree: no delete attempted"
fi

# 7. Orca must actually be told to run the hook on removal.
if [[ -f $ROOT/orca.yaml ]] && grep -qF 'archive:' "$ROOT/orca.yaml" &&
	grep -qF 'scripts/cleanup-worktree-vm.sh' "$ROOT/orca.yaml"; then
	pass "orca.yaml declares the archive hook"
else
	fail "orca.yaml declares the archive hook"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all vm-cleanup checks passed\n'
