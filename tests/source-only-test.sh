#!/usr/bin/env bash
#
# source-only-test.sh — black-box tests for tests/source-only-check.sh.
# Hermetic: only temp fixtures; no repo script is sourced or executed.
# shellcheck disable=SC2016 # fixture shell text is literal, never expanded here

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/tests/source-only-check.sh"
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

# A library script with the standard shape: dispatcher source, one function,
# standalone guard. `$2` injects an extra top-level line when needed.
fixture() {
	local dest=$1 inject=$2 name=$3
	{
		printf '#!/usr/bin/env bash\n'
		printf 'source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"\n'
		[[ -n $inject ]] && printf '%s\n' "$inject"
		printf '%s() {\n\t:\n}\n' "$name"
		printf 'if [[ ${BASH_SOURCE[0]} == "$0" ]]; then\n\tdispatch_command "$@"\nfi\n'
	} >"$dest"
}

fixture "$T/valid.sh" '' install_fixture
fixture "$T/command.sh" 'echo "SIDE EFFECT"' install_fixture
fixture "$T/nofunc.sh" '' fixture_version
fixture "$T/cmdsub.sh" 'X="$(echo hi)"' install_fixture

# Safe top-level declarations: literals, a multiline array, and a heredoc
# whose data contains a column-0 '}' must not be mistaken for commands.
cat >"$T/declarations.sh" <<'EOF'
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"
CONST='literal'
MAP=(
	"a b"
)

verify() {
	cat <<'DATA'
profile x {
}
DATA
}

install_fixture() {
	:
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
EOF

# Subshell-style function: the column-0 ')' closer must end the body.
cat >"$T/subshell.sh" <<'EOF'
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

fixture_verify() (
	:
)

install_fixture() {
	:
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
EOF

# check <name> <expected-status> <file> [output-substring]
check() {
	local name=$1 want=$2 file=$3 pattern=${4:-}
	local out status
	out="$(bash "$CHECK" "$file" 2>&1)"
	status=$?
	if [[ $status -eq $want ]] && [[ -z $pattern || $out == *"$pattern"* ]]; then
		pass "$name"
	else
		fail "$name (status=$status want=$want out=$out)"
	fi
}

check "valid script passes" 0 "$T/valid.sh"
check "top-level command fails" 1 "$T/command.sh" "top-level command"
check "no install/config function fails" 1 "$T/nofunc.sh" "no install_*/config_* function"
check "command substitution at top level fails" 1 "$T/cmdsub.sh" "top-level command"
check "inert declarations pass" 0 "$T/declarations.sh"
check "subshell-style function passes" 0 "$T/subshell.sh"

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all source-only checks passed\n'
