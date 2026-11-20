#!/usr/bin/env bash
#
# anythingllm-test.sh — use-case tests for the AnythingLLM Desktop installer.
# Black-box: only exit codes, stdout markers and filesystem state are asserted,
# never helper names or code layout. Hermetic: stubbed curl/sudo/apparmor_parser/
# uname, sandboxed HOME with the installer's own env knobs pinned inside it,
# release JSON fixture generated with the real sha256 of a
# fake AppImage. No network, no 905 MB download, no /etc write is ever touched.
# Fail-closed: any failure exits 1.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${ANYTHINGLLM_SRC:-$ROOT/setup/desktop-apps/anythingllm.sh}"
TAG="v1.19.0"
ASSET="AnythingLLMDesktop.AppImage"
ARM_ASSET="AnythingLLMDesktop-Arm64.AppImage"
FAILURES=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	printf 'ok: %s\n' "$1"
}

if ! command -v python3 >/dev/null 2>&1; then
	printf 'skip: whole file (python3 missing)\n'
	exit 0
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/arm" "$T/sysbin" "$T/home" "$T/tmp"
export HOME="$T/home"
export TMPDIR="$T/tmp"
# Pin the script's env knobs to the sandbox. Sandboxing HOME alone is not
# enough: a developer who exports ANYTHING_LLM_INSTALL_DIR or XDG_STATE_HOME
# would have the suite write the fake payload over their real install.
export ANYTHING_LLM_INSTALL_DIR="$HOME/Applications"
export XDG_STATE_HOME="$HOME/.local/state"
STUB_DIR="$T/stubs"
mkdir -p "$STUB_DIR"
export STUB_DIR
APP="$HOME/Applications/$ASSET"
MARKER="$HOME/.local/state/ubuntu-config/anythingllm.version"
DESKTOP="$HOME/.local/share/applications/anythingllmdesktop.desktop"
PROFILE="/etc/apparmor.d/anythingllmdesktop"
export APP MARKER DESKTOP PROFILE TAG ASSET ARM_ASSET

# Coreutils the script needs, so PATH stays closed to real app binaries.
for b in awk bash basename cat chmod cp dirname grep head mkdir mktemp mv rm sed sha256sum stat touch tr uname; do
	ln -s "$(command -v "$b")" "$T/sysbin/$b"
done
ln -s "$(command -v python3)" "$T/sysbin/python3"

# Fixture AppImage: tiny file, real digest computed over it.
printf 'fake AppImage payload\n' >"$STUB_DIR/fake.AppImage"
GOOD_SHA="$(sha256sum "$STUB_DIR/fake.AppImage" | cut -d' ' -f1)"
export GOOD_SHA

# release_json <out> <asset-name> <digest-or-none> <decoy-name> <tag> — mirrors
# the shape of GitHub's REST response (indent=2, one field per line). The decoy
# asset always carries a wrong digest, so a parser that matched the wrong entry
# fails verification instead of passing by accident.
release_json() {
	python3 - "$1" "$2" "$3" "$4" "$5" <<'PYEOF'
import json, sys
out, name, digest, decoy, tag = sys.argv[1:6]
asset = {"name": name, "size": 20, "state": "uploaded"}
if digest != "none":
    asset["digest"] = "sha256:" + digest
payload = {
    "tag_name": tag,
    "assets": [
        {"name": decoy, "size": 1, "state": "uploaded", "digest": "sha256:" + "a" * 64},
        asset,
    ],
}
with open(out, "w") as f:
    json.dump(payload, f, indent=2)
PYEOF
}
set_release() {
	local want=${1:-$ASSET} decoy=$ARM_ASSET
	[[ $want == "$ARM_ASSET" ]] && decoy=$ASSET
	release_json "$STUB_DIR/release.json" "$want" "${2:-$GOOD_SHA}" "$decoy" "${3:-$TAG}"
}
set_release

# Stub curl: serves the API JSON or the fixture artifact, whichever URL is asked
# for, and logs every URL. Fails when fail-curl exists.
cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
url=""
dest=""
prev=""
for a in "$@"; do
	case $a in
	http*) url=$a ;;
	esac
	[[ $prev == "-o" ]] && dest=$a
	prev=$a
done
printf '%s\n' "$url" >>"$STUB_DIR/curl-urls"
[[ -f $STUB_DIR/fail-curl ]] && exit 6
case $url in
*api.github.com*) cat "$STUB_DIR/release.json" ;;
*releases/download/*) cp "$STUB_DIR/fake.AppImage" "$dest" ;;
*) exit 22 ;;
esac
EOF
# Stub sudo: always succeeds, logs invocations (proves what needs root).
cat > "$T/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_DIR/sudo-calls"
exit 0
EOF
# Stub apparmor_parser: reports a 4.x version and logs the reload.
cat > "$T/bin/apparmor_parser" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == --version ]]; then
	printf 'AppArmor version 4.0.1\n'
	exit 0
fi
printf '%s\n' "$*" >>"$STUB_DIR/parser-calls"
exit 0
EOF
# Stub uname for the arm64 case (shadowed only via $T/arm).
cat > "$T/arm/uname" <<'EOF'
#!/usr/bin/env bash
printf 'aarch64\n'
EOF
chmod +x "$T/bin/"* "$T/arm/uname"

call() {
	PATH="$T/bin:$T/sysbin" bash "$SRC" "$@" </dev/null
}

call_arm() {
	PATH="$T/arm:$T/bin:$T/sysbin" bash "$SRC" "$@" </dev/null
}

version_of() {
	bash "$SRC" version 2>/dev/null
}

apparmor_enabled() { [[ -f /sys/kernel/security/apparmor/profiles ]]; }

# U1. Fresh install leaves a launchable app and an honest version.
rm -f "$STUB_DIR/sudo-calls"
out=$(call install 2>&1); rc=$?
if [[ $rc -eq 0 && -x $APP && $(version_of) == "1.19.0" &&
	$(grep -cE "^Exec=\"[^\"]*$ASSET\"$" "$DESKTOP") -eq 1 &&
	! -e "$HOME/Applications/$ASSET.part" ]]; then
	pass "fresh install verifies, installs and reports 1.19.0"
else
	fail "fresh install verifies, installs and reports 1.19.0 (rc=$rc out=$out)"
fi

# U2. Profile handling follows the host, and never fails the step either way.
# The profile lives at an absolute /etc path, so which branch is reachable
# depends on the machine running the suite: assert the branch that exists.
if ! apparmor_enabled; then
	if [[ $rc -eq 0 && $out == *"skip: apparmor not detected"* ]]; then
		pass "apparmor-less host: silent skip, step still succeeded"
	else
		fail "apparmor-less host: silent skip, step still succeeded (rc=$rc out=$out)"
	fi
elif [[ -f $PROFILE ]]; then
	if [[ $rc -eq 0 ]] && ! grep -qF "$PROFILE" "$STUB_DIR/sudo-calls" 2>/dev/null; then
		pass "existing profile is never rewritten"
	else
		fail "existing profile is never rewritten (sudo-calls: $(cat "$STUB_DIR/sudo-calls" 2>/dev/null))"
	fi
elif grep -qF "install -m 0644" "$STUB_DIR/sudo-calls" 2>/dev/null &&
	grep -qF "apparmor_parser -r $PROFILE" "$STUB_DIR/sudo-calls" 2>/dev/null; then
	pass "apparmor host: profile written and reloaded"
else
	fail "apparmor host: profile written and reloaded (sudo-calls: $(cat "$STUB_DIR/sudo-calls" 2>/dev/null))"
fi

# U3. Re-run skips the download entirely (idempotency guard, no network).
# Asserted on the guard's wording, not a bare "skip:" prefix, which the cheap
# state helpers also print (e.g. apparmor-less hosts).
: >"$STUB_DIR/curl-urls"
out=$(call install 2>&1); rc=$?
if [[ $rc -eq 0 && $out == *"anythingllm already installed"* && ! -s $STUB_DIR/curl-urls ]]; then
	pass "re-run skips without touching the network"
else
	fail "re-run skips without touching the network (rc=$rc out=$out)"
fi

# U4. A user-edited .desktop is never clobbered by a rerun.
printf '# edited-by-user\n' >>"$DESKTOP"
call install >/dev/null 2>&1
if tail -n 1 "$DESKTOP" | grep -q 'edited-by-user'; then
	pass "rerun preserves a hand-edited desktop entry"
else
	fail "rerun preserves a hand-edited desktop entry"
fi

# U5. Mismatching digest fails closed: nothing installed, nothing left behind.
rm -f "$APP" "$MARKER"
set_release "$ASSET" "$(printf 'b%.0s' {1..64})"
out=$(call install 2>&1); rc=$?
if [[ $rc -ne 0 && $out == *mismatch* && ! -e $APP && ! -e "$HOME/Applications/$ASSET.part" &&
	! -e $MARKER && $(version_of 2>/dev/null; echo "rc=$?") == *"rc=1"* ]]; then
	pass "digest mismatch aborts and installs nothing"
else
	fail "digest mismatch aborts and installs nothing (rc=$rc out=$out)"
fi

# U6. No published digest is an error, not an unverified install.
set_release "$ASSET" none
out=$(call install 2>&1); rc=$?
if [[ $rc -ne 0 && ! -e $APP && ! -e $MARKER && ! -e "$HOME/Applications/$ASSET.part" ]]; then
	pass "missing digest fails closed"
else
	fail "missing digest fails closed (rc=$rc out=$out)"
fi

# U7. The wanted asset absent from the release is also a hard error.
set_release "Other.Asset" "$GOOD_SHA"
out=$(call install 2>&1); rc=$?
if [[ $rc -ne 0 && ! -e $APP ]]; then
	pass "unknown asset in release fails closed"
else
	fail "unknown asset in release fails closed (rc=$rc out=$out)"
fi

# U8. Architecture selects the arm64 artifact.
set_release "$ARM_ASSET" "$GOOD_SHA"
: >"$STUB_DIR/curl-urls"
out=$(call_arm install 2>&1); rc=$?
if [[ $rc -eq 0 && -x $APP && $(grep -c "releases/download/$TAG/$ARM_ASSET" "$STUB_DIR/curl-urls") -eq 1 ]]; then
	pass "aarch64 installs the arm64 artifact"
else
	fail "aarch64 installs the arm64 artifact (rc=$rc out=$out urls=$(cat "$STUB_DIR/curl-urls"))"
fi

# U9. Once installed, a dead network is a no-op: the guard never re-hits it.
set_release "$ASSET" "$GOOD_SHA"
call install >/dev/null 2>&1
touch "$STUB_DIR/fail-curl"
out=$(call install 2>&1); rc=$?
rm -f "$STUB_DIR/fail-curl"
if [[ $rc -eq 0 && $out == *"anythingllm already installed"* && -x $APP && $(version_of) == "1.19.0" ]]; then
	pass "installed app is never re-downloaded, so dead network is a no-op"
else
	fail "installed app is never re-downloaded, so dead network is a no-op (rc=$rc out=$out)"
fi

# U10. Removing the artifact makes the guard go false and reinstall it.
rm -f "$APP"
out=$(call install 2>&1); rc=$?
if [[ $rc -eq 0 && $out != *"anythingllm already installed"* && -x $APP ]]; then
	pass "missing artifact reinstalls instead of trusting the marker"
else
	fail "missing artifact reinstalls instead of trusting the marker (rc=$rc out=$out)"
fi

# U11. An empty marker is not a version (skip guard must not go silent).
# The artifact stays in place, so only the marker can fail the guard here.
: >"$MARKER"
if version_of >/dev/null 2>&1; then
	fail "empty marker must not report installed"
else
	pass "empty marker does not report installed"
fi

# U12. An install dir with a space still launches: the desktop-entry spec
# requires quoting an Exec argument that leaves its safe set, so an unquoted
# path would end the executable name at the space.
SPACED="$HOME/My Apps"
mkdir -p "$SPACED"
rm -f "$DESKTOP"
out=$(ANYTHING_LLM_INSTALL_DIR="$SPACED" PATH="$T/bin:$T/sysbin" bash "$SRC" install 2>&1); rc=$?
if [[ $rc -eq 0 && -x "$SPACED/$ASSET" &&
	$(grep -c "^Exec=\"$SPACED/$ASSET\"$" "$DESKTOP") -eq 1 ]]; then
	pass "spaced install dir yields a quoted launcher entry"
else
	fail "spaced install dir yields a quoted launcher entry (rc=$rc out=$out entry=$(cat "$DESKTOP" 2>/dev/null | grep '^Exec'))"
fi

# U13. versions.sh reports the row end to end on a closed PATH.
set_release "$ASSET" "$GOOD_SHA"
rm -f "$MARKER"
call install >/dev/null 2>&1
out=$(PATH="$T/bin:$T/sysbin" bash "$ROOT/reports/versions.sh" 2>/dev/null)
if [[ $out == *"| anythingllm | 1.19.0 |"* ]]; then
	pass "versions report covers anythingllm"
else
	fail "versions report covers anythingllm (out=$(printf '%s' "$out" | grep anythingllm))"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all anythingllm checks passed\n'
