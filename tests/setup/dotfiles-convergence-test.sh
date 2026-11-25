#!/usr/bin/env bash
#
# dotfiles-convergence-test.sh — hermetic checks for issue #82.
# Stubs curl with a fake oh-my-zsh installer that records its arguments; no
# network, sudo, real installer, or host dotfile is touched. Fail-closed.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILURES=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	printf 'ok: %s\n' "$1"
}

check_line() {
	local name=$1 file=$2 line=$3
	if [[ -f $file ]] && grep -Fxq -- "$line" "$file"; then
		pass "$name: $line"
	else
		fail "$name: missing $line"
	fi
}

T="$(mktemp -d)" || {
	printf 'error: mktemp failed, refusing to run\n' >&2
	exit 1
}
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stubs" "$T/home"

# The fake installer writes the arguments it received, one per line. The empty
# $0 the real call must pass is part of what this test checks.
cat > "$T/stubs/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' 'printf "%s\n" "$@" > "$OMZ_ARGS_FILE"'
STUB
chmod +x "$T/stubs/curl"

export HOME="$T/home"
export PATH="$T/stubs:$PATH"
export OMZ_ARGS_FILE="$T/omz-args"

source "$ROOT/setup/development/oh-my-zsh/oh-my-zsh.sh"

out="$(install_oh_my_zsh 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then
	pass "installer runs: status 0"
else
	fail "installer runs: expected status 0, got $rc ($out)"
fi
check_line "installer flags" "$OMZ_ARGS_FILE" --keep-zshrc
check_line "installer flags" "$OMZ_ARGS_FILE" --unattended

# A second run must skip the installer and leave no new arguments behind.
: > "$OMZ_ARGS_FILE"
mkdir -p "$HOME/.oh-my-zsh"
out="$(install_oh_my_zsh 2>&1)"
rc=$?
if [[ $rc -eq 0 && $out == skip:* ]]; then
	pass "installed guard: skipped ($out)"
else
	fail "installed guard: expected skip with status 0, got $rc ($out)"
fi
if [[ ! -s $OMZ_ARGS_FILE ]]; then
	pass "installed guard: installer not run again"
else
	fail "installed guard: installer ran again"
fi

if grep -qF 'chezmoi apply --force --source' "$ROOT/setup/install.sh"; then
	pass "chezmoi step: applies with --force"
else
	fail "chezmoi step: missing --force on the apply command"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all checks passed\n'
