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

# A caller waits for EOF on stdout, just as a remote exec does. A loop that
# inherits stdout keeps this wait alive until its background sleep ends.
wait_for_eof_ms() {
	local script=$1 start end out
	start=$(date +%s%3N)
	out=$(bash "$script" | cat)
	end=$(date +%s%3N)
	[[ $out == *done* ]] || return 2
	printf '%s' "$((end - start))"
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
			-e 's/sleep 50/sleep 0.4/')
	printf '#!/usr/bin/env bash\n%s\nprintf "done\\n"\n' "$stub" > "$T/$name"
	chmod +x "$T/$name"

	elapsed=$(wait_for_eof_ms "$T/$name") || {
		fail "$name: stub produced no output"
		continue
	}
	if [[ $elapsed -lt 200 ]]; then
		pass "$name: output stream released ($elapsed ms)"
	else
		fail "$name: output stream held open ($elapsed ms)"
	fi
done

[[ $FAILURES -eq 0 ]] || exit 1
