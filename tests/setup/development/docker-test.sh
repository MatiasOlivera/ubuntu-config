#!/usr/bin/env bash
#
# docker-test.sh — hermetic checks for install_docker (issue #163).
# Stubs sudo/docker/newgrp; no apt, group changes or shell hijacking on the host.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="$ROOT/setup/development/docker.sh"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home"
export STUB_DIR="$T" HOME="$T/home" USER=test-user

cat > "$T/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/sudo-calls"
EOF
cat > "$T/bin/docker" <<'EOF'
#!/usr/bin/env bash
case "$*" in
	--version) printf 'Docker version 28.0.0, build stub\n' ;;
	'compose version') printf 'Docker Compose version v2.35.0\n' ;;
esac
EOF
cat > "$T/bin/newgrp" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/newgrp-calls"
EOF
chmod +x "$T/bin"/*
PATH="$T/bin:$PATH"
export PATH

bash -c '
	source "$1"
	install_docker
	printf "caller-continued\n"
' _ "$SRC" >"$T/out" 2>&1
status=$?

if [[ $status -eq 0 ]]; then
	pass "install_docker: status 0"
else
	fail "install_docker: status $status"
fi
if grep -q 'caller-continued' "$T/out"; then
	pass "install_docker: caller continues"
else
	fail "install_docker: caller stopped early"
fi
if [[ ! -e $T/newgrp-calls ]]; then
	pass "install_docker: no newgrp mid-run"
else
	fail "install_docker: invoked newgrp mid-run"
fi
if grep -qx 'groupadd -f docker' "$T/sudo-calls" 2>/dev/null; then
	pass "install_docker: docker group ensured"
else
	fail "install_docker: docker group not ensured"
fi
if grep -qx "usermod -aG docker $USER" "$T/sudo-calls" 2>/dev/null; then
	pass "install_docker: user added to docker group"
else
	fail "install_docker: user not added to docker group"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all docker checks passed\n'
