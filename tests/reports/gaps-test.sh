#!/usr/bin/env bash
#
# gaps-test.sh — use-case tests for the AppImage section of reports/gaps.sh.
# Black-box: only the printed table is asserted, never function names or code
# layout. Hermetic: fixture HOME, stubbed package managers, no apt/snap/flatpak
# and no network. Host directories (/opt, /usr/share/applications) may add rows,
# so every assertion is about the fixture's own candidates. Fail-closed: any
# failure exits 1.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/reports/gaps.sh"
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
H="$T/home"
mkdir -p "$H/Applications" "$H/.local/share/applications" "$H/.local/bin" "$T/bin"

# Stub package managers: the apt/snap/flatpak sections must stay empty so only
# the AppImage section is under test.
for m in apt-mark snap flatpak dpkg-query; do
	printf '#!/usr/bin/env bash\nexit 0\n' >"$T/bin/$m"
done
chmod +x "$T/bin/"*

printf 'x\n' >"$H/Applications/My Tool.AppImage"
printf 'x\n' >"$H/Applications/AnythingLLMDesktop.AppImage"
printf 'x\n' >"$H/Applications/plain.AppImage"

# Three launcher shapes: a quoted path with a space, a quoted path whose
# directory contains an escaped quote, and an unquoted path with arguments.
printf '[Desktop Entry]\nExec="%s/My Tool.AppImage" %%U\n' "$H/Applications" >"$H/.local/share/applications/spaced.desktop"
printf '[Desktop Entry]\nExec="%s/My\\"Apps/Weird Name.AppImage"\n' "$H" >"$H/.local/share/applications/escaped.desktop"
printf '[Desktop Entry]\nExec=%s/Applications/plain.AppImage --flag\n' "$H" >"$H/.local/share/applications/plain.desktop"

out="$(HOME="$H" PATH="$T/bin:/usr/bin:/bin" bash "$SRC" 2>/dev/null)"
section="$(printf '%s\n' "$out" | sed -n '/^AppImage$/,$p')"

row() {
	local needle="| $1 |"
	[[ $section == *"$needle"* ]]
}

# G1. A spaced path is one candidate, not two.
if row "My Tool.AppImage"; then
	pass "spaced AppImage path stays one candidate"
else
	fail "spaced AppImage path stays one candidate (section=$section)"
fi

# G2. An escaped quote inside a quoted Exec does not end the path: the
# candidate is the file name, not the fragment before the escape.
if row "Weird Name.AppImage" && ! printf '%s\n' "$section" | grep -q 'My\\'; then
	pass "escaped quote parsed to the real file name"
else
	fail "escaped quote parsed to the real file name (section=$section)"
fi

# G3. An unquoted Exec still stops at its first argument.
if row "plain.AppImage"; then
	pass "unquoted Exec yields the path, not the arguments"
else
	fail "unquoted Exec yields the path, not the arguments (section=$section)"
fi

# G4. Anything setup installs is never reported as a gap.
if ! row "AnythingLLMDesktop.AppImage"; then
	pass "managed AppImage is filtered out"
else
	fail "managed AppImage is filtered out (section=$section)"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all gaps checks passed\n'
