#!/usr/bin/env bash
#
# credential-sync-test.sh — functional test for setup/security/credential-sync.sh.
# Stubs secret-tool/bw on PATH with file-backed fakes, so no real keyring,
# vault, or network is ever touched. Stored values are obvious dummies.
# Fail-closed: any failure exits 1.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="$ROOT/setup/security/credential-sync.sh"
export SRC
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
mkdir -p "$T/bin" "$T/data"
export STUB_DIR="$T/data"

# Stub secret-tool: lookup prints the entry or exits 1; store writes stdin.
cat > "$T/bin/secret-tool" <<'EOF'
#!/usr/bin/env bash
svc=""; acc=""; op=$1; shift
while [[ $# -gt 0 ]]; do
	case $1 in
	--label) shift 2 ;;
	service) svc=$2; shift 2 ;;
	account) acc=$2; shift 2 ;;
	*) shift ;;
	esac
done
f="$STUB_DIR/keyring-$svc-$acc"
if [[ $op == lookup ]]; then
	[[ -f $f ]] && cat "$f" && exit 0 || exit 1
elif [[ $op == store ]]; then
	cat > "$f"
	exit 0
fi
exit 2
EOF
# Stub bw: logs every call; unlock succeeds only with a tty (like the real
# CLI); status reports unauthenticated when $STUB_DIR/bw-logged-out exists;
# sync fails when $STUB_DIR/fail-sync exists; get serves vault files.
cat > "$T/bin/bw" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$STUB_DIR/bw-calls"
if [[ $1 == status ]]; then
	if [[ -f $STUB_DIR/bw-logged-out ]]; then
		printf '%s\n' '{"status":"unauthenticated"}'
	else
		printf '%s\n' '{"status":"unlocked"}'
	fi
	exit 0
elif [[ $1 == login ]]; then
	rm -f "$STUB_DIR/bw-logged-out"
	exit 0
elif [[ $1 == unlock ]]; then
	if [[ -t 0 ]]; then
		echo stub-session
		exit 0
	else
		echo "vault locked" >&2
		exit 1
	fi
elif [[ $1 == sync ]]; then
	[[ -f $STUB_DIR/fail-sync ]] && exit 1 || exit 0
elif [[ $1 == get ]]; then
	f="$STUB_DIR/vault-$3"
	[[ -f $f ]] && cat "$f" && exit 0 || exit 1
elif [[ $1 == lock ]]; then
	exit 0
fi
exit 2
EOF
chmod +x "$T/bin/secret-tool" "$T/bin/bw"

# Runner sources the real script, then calls the function. PRELUDE optionally
# points at a file sourced first (used to override SECRETS_MAP).
cat > "$T/run.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091 # SRC/PRELUDE are set by the test harness
source "$SRC"
[[ -n ${PRELUDE:-} ]] && source "$PRELUDE"
config_sync_credentials "$@"
EOF
chmod +x "$T/run.sh"

seed() { # $1=item $2=keyring-value $3=vault-value $4=service $5=account
	printf '%s' "$2" > "$STUB_DIR/keyring-$4-$5"
	printf '%s' "$3" > "$STUB_DIR/vault-$1"
}

keyring() { # $1=service $2=account
	cat "$STUB_DIR/keyring-$1-$2"
}

call() { # no tty: stdin from /dev/null
	PATH="$T/bin:$PATH" bash "$T/run.sh" "$@" </dev/null
}

call_tty() { # with a pty so the stub unlock succeeds; strips CRs from output
	PATH="$T/bin:$PATH" script -qec "$T/run.sh $*" /dev/null </dev/null > "$T/tty.out" 2>&1
	local rc=$?
	tr -d '\r' < "$T/tty.out"
	return $rc
}

if ! command -v script >/dev/null 2>&1; then
	printf 'skip: tty cases (script not installed)\n'
	HAS_TTY=0
else
	HAS_TTY=1
fi

# 1. default re-run skips present entries (the stale-token rotation bug).
seed github-mcp-pat OLD NEW github-mcp personal-access-token
out=$(call 2>&1); rc=$?
if [[ $rc -eq 0 && $out == *present:* && $(keyring github-mcp personal-access-token) == OLD ]]; then
	pass "default skips present entry"
else
	fail "default skips present entry (rc=$rc out=$out)"
fi

# 2. --force re-syncs a stale-but-present entry.
if [[ $HAS_TTY -eq 1 ]]; then
	out=$(call_tty --force github-mcp-pat); rc=$?
	if [[ $rc -eq 0 && $out == *synced:* && $(keyring github-mcp personal-access-token) == NEW ]]; then
		pass "--force <item> re-syncs stale entry"
	else
		fail "--force <item> re-syncs stale entry (rc=$rc out=$out)"
	fi
else
	printf 'skip: --force <item> re-syncs stale entry\n'
fi

# 3. -f is an alias for --force.
if [[ $HAS_TTY -eq 1 ]]; then
	printf '%s' OLD > "$STUB_DIR/keyring-github-mcp-personal-access-token"
	out=$(call_tty -f github-mcp-pat); rc=$?
	if [[ $rc -eq 0 && $out == *synced:* && $(keyring github-mcp personal-access-token) == NEW ]]; then
		pass "-f aliases --force"
	else
		fail "-f aliases --force (rc=$rc out=$out)"
	fi
else
	printf 'skip: -f aliases --force\n'
fi

# 4. bare --force re-syncs every mapped entry.
if [[ $HAS_TTY -eq 1 ]]; then
	printf '%s' OLD > "$STUB_DIR/keyring-github-mcp-personal-access-token"
	out=$(call_tty --force); rc=$?
	if [[ $rc -eq 0 && $out == *synced:* && $(keyring github-mcp personal-access-token) == NEW ]]; then
		pass "bare --force re-syncs all"
	else
		fail "bare --force re-syncs all (rc=$rc out=$out)"
	fi
else
	printf 'skip: bare --force re-syncs all\n'
fi

# 5. --force with a two-entry map touches only the named item.
if [[ $HAS_TTY -eq 1 ]]; then
	cat > "$T/two-entries.sh" <<'EOF'
SECRETS_MAP=("item-a svc-a acc-a" "item-b svc-b acc-b")
EOF
	seed item-a OLD-A NEW-A svc-a acc-a
	seed item-b OLD-B NEW-B svc-b acc-b
	export PRELUDE="$T/two-entries.sh"
	out=$(call_tty --force item-b); rc=$?
	unset PRELUDE
	if [[ $rc -eq 0 && $(keyring svc-a acc-a) == OLD-A && $(keyring svc-b acc-b) == NEW-B ]]; then
		pass "--force <item> leaves other entries alone"
	else
		fail "--force <item> leaves other entries alone (rc=$rc)"
	fi
else
	printf 'skip: --force <item> leaves other entries alone\n'
fi

# 6. unknown item fails fast without unlocking.
out=$(call --force bogus 2>&1); rc=$?
if [[ $rc -eq 1 && $out == *unknown* ]]; then
	pass "unknown item exits 1"
else
	fail "unknown item exits 1 (rc=$rc out=$out)"
fi

# 7. positional args without --force are a usage error.
out=$(call github-mcp-pat 2>&1); rc=$?
if [[ $rc -eq 2 && $out == *usage:* ]]; then
	pass "item without --force exits 2"
else
	fail "item without --force exits 2 (rc=$rc out=$out)"
fi

# 8. --force stays fail-closed without a tty.
printf '%s' OLD > "$STUB_DIR/keyring-github-mcp-personal-access-token"
out=$(call --force 2>&1); rc=$?
if [[ $rc -eq 0 && $out == *pending:* && $(keyring github-mcp personal-access-token) == OLD ]]; then
	pass "--force without tty stays pending"
else
	fail "--force without tty stays pending (rc=$rc out=$out)"
fi

# 9. vault sync runs after unlock and before the first get.
if [[ $HAS_TTY -eq 1 ]]; then
	: > "$STUB_DIR/bw-calls"
	printf '%s' OLD > "$STUB_DIR/keyring-github-mcp-personal-access-token"
	out=$(call_tty --force github-mcp-pat 2>&1); rc=$?
	mapfile -t calls < "$STUB_DIR/bw-calls"
	if [[ $rc -eq 0 && ${calls[0]} == status && ${calls[1]} == unlock && ${calls[2]} == sync && ${calls[3]} == get ]]; then
		pass "vault syncs after unlock, before get"
	else
		fail "vault syncs after unlock, before get (rc=$rc calls=${calls[*]})"
	fi
else
	printf 'skip: vault syncs after unlock, before get\n'
fi

# 10. failed sync aborts without touching the keyring, and locks the vault.
if [[ $HAS_TTY -eq 1 ]]; then
	: > "$STUB_DIR/bw-calls"
	touch "$STUB_DIR/fail-sync"
	printf '%s' OLD > "$STUB_DIR/keyring-github-mcp-personal-access-token"
	out=$(call_tty --force github-mcp-pat 2>&1); rc=$?
	rm -f "$STUB_DIR/fail-sync"
	mapfile -t calls < "$STUB_DIR/bw-calls"
	if [[ $rc -eq 1 && $out == *could\ not\ sync* && $(keyring github-mcp personal-access-token) == OLD ]] && printf '%s\n' "${calls[@]}" | grep -qx lock; then
		pass "failed sync aborts, keyring untouched, vault locked"
	else
		fail "failed sync aborts, keyring untouched, vault locked (rc=$rc out=$out calls=${calls[*]})"
	fi
else
	printf 'skip: failed sync aborts, keyring untouched, vault locked\n'
fi

# 11. logged-out CLI logs in, then the sync proceeds.
if [[ $HAS_TTY -eq 1 ]]; then
	: > "$STUB_DIR/bw-calls"
	touch "$STUB_DIR/bw-logged-out"
	printf '%s' OLD > "$STUB_DIR/keyring-github-mcp-personal-access-token"
	printf '%s' NEWVAL > "$STUB_DIR/vault-github-mcp-pat"
	out=$(call_tty --force github-mcp-pat 2>&1); rc=$?
	rm -f "$STUB_DIR/bw-logged-out"
	mapfile -t calls < "$STUB_DIR/bw-calls"
	if [[ $rc -eq 0 && $out == *synced:* && $(keyring github-mcp personal-access-token) == NEWVAL ]] && [[ ${calls[0]} == status && ${calls[1]} == login && ${calls[2]} == unlock ]]; then
		pass "logged-out CLI logs in, then syncs"
	else
		fail "logged-out CLI logs in, then syncs (rc=$rc out=$out calls=${calls[*]})"
	fi
else
	printf 'skip: logged-out CLI logs in, then syncs\n'
fi

# 12. missing vault item reports an error and leaves the keyring untouched.
if [[ $HAS_TTY -eq 1 ]]; then
	printf '%s' OLD > "$STUB_DIR/keyring-github-mcp-personal-access-token"
	rm -f "$STUB_DIR/vault-github-mcp-pat"
	out=$(call_tty --force github-mcp-pat 2>&1); rc=$?
	if [[ $rc -eq 1 && $out == *could\ not\ sync* && $out != *synced:* && $(keyring github-mcp personal-access-token) == OLD ]]; then
		pass "missing item errors, keyring untouched"
	else
		fail "missing item errors, keyring untouched (rc=$rc out=$out)"
	fi
else
	printf 'skip: missing item errors, keyring untouched\n'
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all credential-sync checks passed\n'
