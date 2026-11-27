#!/usr/bin/env bash
#
# keepalive-stream-test.sh — the sudo keepalive must not hold the caller's
# output stream open after a setup script exits. Reproduces the Multipass exec
# EOF wait with a stubbed, short-lived copy of the real loop.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

# A caller waits for EOF on its output streams, just as a remote exec does.
# The stub's loop prints a sentinel after its sleep: a loop that inherits the
# caller's stream leaks that sentinel into the captured output.
capture_output() {
	local out
	out=$(bash "$1" 2>&1 | cat) || return 1
	[[ $out == *done* ]] || return 2
	printf '%s' "$out"
}

for script in "$ROOT/setup/install.sh" "$ROOT/setup/post-install.sh"; do
	name=$(basename "$script")
	line=$(grep -m1 'while true; do sudo -n true' "$script" 2>/dev/null) || {
		fail "$name: keepalive loop not found"
		continue
	}

	# Keep the loop's real redirection; stub the commands and shorten the sleep.
	stub=$(printf '%s\n' "$line" |
		sed -e 's/sudo -n true/:/' \
			-e 's/sleep 50/sleep 0.4; printf "LEAK\\n"; printf "LEAK\\n" >\&2/')
	printf '#!/usr/bin/env bash\n%s\nprintf "done\\n"\n' "$stub" > "$T/$name"
	chmod +x "$T/$name"

	out=$(capture_output "$T/$name") || {
		fail "$name: stub produced no output"
		continue
	}
	if [[ $out == *LEAK* ]]; then
		fail "$name: keepalive loop leaked to the caller's output stream"
	else
		pass "$name: output stream released"
	fi
done

[[ $FAILURES -eq 0 ]] || exit 1
