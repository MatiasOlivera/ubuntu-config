#!/usr/bin/env bash
# contract-check-test.sh — black-box tests for tests/contract-check.sh.
# Hermetic: temp fixtures only; no repo script is sourced or executed.
# shellcheck disable=SC2016 # fixture shell text is literal, never expanded here

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/tests/contract-check.sh"
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

# check <name> <expected-status> <args...>
check() {
	local name=$1 want=$2
	shift 2
	local out status
	out="$(bash "$CHECK" "$@" 2>&1)"
	status=$?
	if [[ $status -eq $want ]]; then
		pass "$name"
	else
		fail "$name (status=$status want=$want out=$out)"
	fi
}

# Entrypoints: one real source line, one dot-source, one comment-only mention,
# one filename in a string. The second entrypoint has its own source line.
cat >"$T/entries.sh" <<'EOF'
source "$DIR/make.sh"
. "$DIR/other.sh"
# source "$DIR/ghost.sh" was removed
note="curl.sh appears in a string"
EOF
cat >"$T/second.sh" <<'EOF'
source "$DIR/second-lib.sh"
EOF
: >"$T/empty.sh"
for name in make.sh other.sh ghost.sh curl.sh second-lib.sh; do
	: >"$T/$name"
done

cat >"$T/good-config.sh" <<'EOF'
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/dispatcher.sh"

config_good() {
	:
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
EOF

cat >"$T/indented-config.sh" <<'EOF'
#!/usr/bin/env bash
config_indented() {
	:
}
	if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
		dispatch_command "$@"
	fi
EOF

# The dispatcher source line contains BASH_SOURCE but there is no guard.
cat >"$T/no-guard-config.sh" <<'EOF'
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/dispatcher.sh"

config_no_guard() {
	:
}
EOF

cat >"$T/commented-guard-config.sh" <<'EOF'
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/dispatcher.sh"

config_commented() {
	:
}
# if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
# 	dispatch_command "$@"
# fi
EOF

cat >"$T/side-effect-config.sh" <<'EOF'
#!/usr/bin/env bash
touch "$MARKER"

config_side_effect() {
	:
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
EOF

# sourced mode
check "real source statement passes" 0 sourced "$T/entries.sh" "$T/empty.sh" "$T/make.sh"
check "dot source passes" 0 sourced "$T/entries.sh" "$T/empty.sh" "$T/other.sh"
check "source in second entrypoint passes" 0 sourced "$T/empty.sh" "$T/second.sh" "$T/second-lib.sh"
check "comment-only mention fails" 1 sourced "$T/entries.sh" "$T/empty.sh" "$T/ghost.sh"
check "string mention fails" 1 sourced "$T/entries.sh" "$T/empty.sh" "$T/curl.sh"

# guard mode
check "canonical guard passes" 0 guard "$T/good-config.sh"
check "indented guard passes" 0 guard "$T/indented-config.sh"
check "no guard fails" 1 guard "$T/no-guard-config.sh"
check "commented guard fails" 1 guard "$T/commented-guard-config.sh"
MARKER="$T/EXECUTED" check "guard with top-level command passes" 0 guard "$T/side-effect-config.sh"
if [[ -e $T/EXECUTED ]]; then
	fail "checker executed fixture code"
else
	pass "checker never executes fixture code"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all contract checks passed\n'
