#!/usr/bin/env bash
#
# deja-vu-test.sh — use-case tests for the Deja Vu GNOME extension installer.
# Black-box: only exit codes, stdout markers and filesystem state are asserted,
# never helper names or code layout. Hermetic: stubbed sudo/curl/unzip/
# glib-compile-schemas/gnome-extensions/dpkg, fixture archive built with
# python3 stdlib, sandboxed HOME and TMPDIR. DEJA_VU_SRC overrides the script
# under test so the same suite runs against temporal mutants. No real network,
# apt, keyring or session is ever touched. Fail-closed: any failure exits 1.

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SRC="${DEJA_VU_SRC:-$ROOT/setup/desktop-apps/gnome-extensions/deja-vu.sh}"
UUID="deja-window@mcast.gnomext.com"
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
mkdir -p "$T/bin" "$T/home" "$T/tmp"
export HOME="$T/home"
export TMPDIR="$T/tmp"
STUB_DIR="$T/stubs"
mkdir -p "$STUB_DIR"
export STUB_DIR
EXT_ROOT="$HOME/.local/share/gnome-shell/extensions"
export EXT_ROOT
LIVE="$EXT_ROOT/$UUID"

# Stub sudo: always succeeds, logs invocations (proves apt runs iff needed).
cat > "$T/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/sudo-calls"
exit 0
EOF
# Stub curl: serves the fixture archive; fails when fail-curl exists.
cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
dest=""
prev=""
for a in "$@"; do
	[[ $prev == "-o" ]] && dest="$a"
	prev="$a"
done
[[ -f $STUB_DIR/fail-curl ]] && exit 1
cp "$STUB_DIR/fixture.zip" "$dest"
EOF
# Stub unzip: extracts via python3 stdlib (real unzip is absent from the
# Docker test image); fails when fail-unzip exists.
cat > "$T/bin/unzip" <<'EOF'
#!/usr/bin/env bash
zip=""
dir=""
prev=""
for a in "$@"; do
	if [[ $prev == "-d" ]]; then
		dir="$a"
	elif [[ $a != -* && -z $zip ]]; then
		zip="$a"
	fi
	prev="$a"
done
[[ -f $STUB_DIR/fail-unzip ]] && exit 1
python3 - "$zip" "$dir" <<'PYEOF'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PYEOF
EOF
# Stub glib-compile-schemas: logs the directory it compiles (proves
# pre-publish ordering: stage, not live) plus both filesystem IDs (proves
# same-filesystem staging), then ships a compiled file.
cat > "$T/bin/glib-compile-schemas" <<'EOF'
#!/usr/bin/env bash
[[ -f $STUB_DIR/fail-compile ]] && exit 1
printf '%s\n' "$1" >> "$STUB_DIR/compile-calls"
stat -c %d "$1" >> "$STUB_DIR/compile-fs"
stat -c %d "$EXT_ROOT" >> "$STUB_DIR/compile-fs"
touch "$1/gschemas.compiled"
EOF
# Stub gnome-extensions: logs enablement; fails when fail-enable exists.
cat > "$T/bin/gnome-extensions" <<'EOF'
#!/usr/bin/env bash
[[ -f $STUB_DIR/fail-enable ]] && exit 1
printf '%s\n' "$*" >> "$STUB_DIR/enable-calls"
exit 0
EOF
# Stub dpkg (for the versions.sh wiring check).
cat > "$T/bin/dpkg" <<'EOF'
#!/usr/bin/env bash
[[ $1 == "-s" && $2 == "gnome-browser-connector" ]] || exit 1
[[ -f $STUB_DIR/dpkg-missing ]] && exit 1
printf 'Package: gnome-browser-connector\nVersion: 42.1-7\n'
EOF
chmod +x "$T/bin/"*

# Minimal coreutils PATH without gnome-extensions: proves the headless
# no-op even on hosts that have the real binary, and keeps the versions.sh
# wiring check hermetic (no real app CLI like cursor can hang the suite).
mkdir -p "$T/sysbin"
for b in awk bash basename cp dirname grep head mkdir mktemp mv python3 rm stat touch tr; do
	p="$(command -v "$b")" && ln -s "$p" "$T/sysbin/$b"
done

# Fixture EGO-like archive: version 17 plus one gschema file.
python3 - "$STUB_DIR" <<'EOF'
import os, sys, zipfile
base = os.path.join(sys.argv[1], "src")
os.makedirs(os.path.join(base, "schemas"))
with open(os.path.join(base, "extension.js"), "w") as f:
    f.write("// fixture")
with open(os.path.join(base, "metadata.json"), "w") as f:
    f.write('{"uuid": "deja-window@mcast.gnomext.com", "version": 17}')
with open(os.path.join(base, "schemas", "org.gnome.shell.extensions.deja-window.gschema.xml"), "w") as f:
    f.write("<schemalist></schemalist>")
with zipfile.ZipFile(os.path.join(sys.argv[1], "fixture.zip"), "w") as z:
    for root, _, files in os.walk(base):
        for fn in files:
            p = os.path.join(root, fn)
            z.write(p, os.path.relpath(p, base))
EOF

call() { # documented standalone interface: install|version|config
	PATH="$T/bin:$PATH" bash "$SRC" "$@" </dev/null
}

call_restricted() { # sysbin only: gnome-extensions is truly absent here
	PATH="$T/sysbin" bash "$SRC" "$@" </dev/null
}

seed_v16() { # downgrade live install + plant a stale file (upgrade fixture)
	sed -i 's/"version": 17/"version": 16/' "$LIVE/metadata.json"
	touch "$LIVE/stale-from-v16"
}

live_version() {
	bash "$SRC" version 2>/dev/null
}

litter() { # stale files or backup leftovers inside the live dir
	ls -A "$LIVE" 2>/dev/null | grep -E '~|^stage$' || true
}

# U1. Fresh install ships a usable extension.
out=$(call install 2>&1); rc=$?
if [[ $rc -eq 0 && $(live_version) == "17" && -f $LIVE/extension.js && -f $LIVE/metadata.json && -f $LIVE/schemas/gschemas.compiled && -z $(litter) ]]; then
	pass "fresh install ships usable v17"
else
	fail "fresh install ships usable v17 (rc=$rc out=$out)"
fi

# U2. Re-run skips without touching apt.
rm -f "$STUB_DIR/sudo-calls"
out=$(call install 2>&1); rc=$?
if [[ $rc -eq 0 && $out == *skip:* && ! -f $STUB_DIR/sudo-calls ]]; then
	pass "re-run skips without apt"
else
	fail "re-run skips without apt (rc=$rc out=$out)"
fi

# U3. Upgrade replaces the old version completely.
seed_v16
out=$(call install 2>&1); rc=$?
if [[ $rc -eq 0 && $(live_version) == "17" && ! -f $LIVE/stale-from-v16 && -z $(litter) ]]; then
	pass "upgrade removes stale files"
else
	fail "upgrade removes stale files (rc=$rc out=$out)"
fi

# U4. Dead network fails loudly and leaves the old version intact.
seed_v16
touch "$STUB_DIR/fail-curl"
out=$(call install 2>&1); rc=$?
rm -f "$STUB_DIR/fail-curl"
if [[ $rc -ne 0 && $(live_version) == "16" && -f $LIVE/stale-from-v16 && -z $(ls -A "$T/tmp") ]]; then
	pass "curl failure keeps old version"
else
	fail "curl failure keeps old version (rc=$rc out=$out)"
fi

# U5. Corrupt archive fails loudly and leaves the old version intact.
seed_v16
touch "$STUB_DIR/fail-unzip"
out=$(call install 2>&1); rc=$?
rm -f "$STUB_DIR/fail-unzip"
if [[ $rc -ne 0 && $(live_version) == "16" && -f $LIVE/stale-from-v16 ]]; then
	pass "unzip failure keeps old version"
else
	fail "unzip failure keeps old version (rc=$rc out=$out)"
fi

# U6. Failed schema compile never publishes: the old version stays live.
seed_v16
touch "$STUB_DIR/fail-compile"
out=$(call install 2>&1); rc=$?
rm -f "$STUB_DIR/fail-compile"
if [[ $rc -ne 0 && $(live_version) == "16" && -f $LIVE/stale-from-v16 ]]; then
	pass "compile failure keeps old version"
else
	fail "compile failure keeps old version (rc=$rc out=$out)"
fi

# U7. A stale backup from a killed run never blocks an upgrade.
seed_v16
mkdir -p "$LIVE.~1~"
touch "$LIVE.~1~/marker"
out=$(call install 2>&1); rc=$?
if [[ $rc -eq 0 && $(live_version) == "17" && -z $(ls -A "$EXT_ROOT" | grep '~' || true) ]]; then
	pass "stale backup does not block upgrade"
else
	fail "stale backup does not block upgrade (rc=$rc out=$out)"
fi

# U8. Staging shares the destination filesystem (atomic publish, no
# cross-filesystem partial copy). /dev/shm is tmpfs: forcing TMPDIR there
# proves the work dir follows the destination, not the temp default.
if [[ -d /dev/shm ]]; then
	seed_v16
	: > "$STUB_DIR/compile-fs"
	out=$(TMPDIR=/dev/shm call install 2>&1); rc=$?
	mapfile -t fs < "$STUB_DIR/compile-fs"
	n=${#fs[@]}
	if [[ $rc -eq 0 && $n -ge 2 && ${fs[n-2]} == "${fs[n-1]}" && $(tail -n 2 "$STUB_DIR/compile-calls" | head -n 1) != "$LIVE" ]]; then
		pass "staging shares destination filesystem"
	else
		fail "staging shares destination filesystem (rc=$rc out=$out)"
	fi
else
	printf 'skip: staging shares destination filesystem (/dev/shm missing)\n'
fi

# U9. Headless machine: config succeeds without gnome-extensions.
out=$(call_restricted config 2>&1); rc=$?
if [[ $rc -eq 0 ]]; then
	pass "headless config is a silent no-op"
else
	fail "headless config is a silent no-op (rc=$rc out=$out)"
fi

# U10. Desktop session: config enables, and enable failures surface.
rm -f "$STUB_DIR/enable-calls"
out=$(call config 2>&1); rc=$?
if [[ $rc -eq 0 && $(cat "$STUB_DIR/enable-calls") == "enable $UUID" ]]; then
	pass "config enables the extension"
else
	fail "config enables the extension (rc=$rc out=$out)"
fi
touch "$STUB_DIR/fail-enable"
out=$(call config 2>&1); rc=$?
rm -f "$STUB_DIR/fail-enable"
if [[ $rc -ne 0 ]]; then
	pass "failed enable surfaces"
else
	fail "failed enable surfaces (rc=$rc out=$out)"
fi

# U11. versions.sh reports both rows (wiring contract, end to end).
# Restricted PATH: only stubs + coreutils resolve, so no real app CLI can
# stall or pollute the run; our rows resolve via the dpkg stub + sandbox HOME.
out=$(PATH="$T/bin:$T/sysbin" bash "$ROOT/reports/versions.sh" 2>/dev/null)
if [[ $out == *"| gnome-browser-connector | Version:"* && $out == *"| deja-vu | 17"* ]]; then
	pass "versions report covers both packages"
else
	fail "versions report covers both packages (out=$out)"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all deja-vu checks passed\n'
