#!/usr/bin/env bash
# versions-test.sh — hermetic test for the report-only version table.
# A closed PATH leaves every tool missing except curl, which is stubbed.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/reports/versions.sh"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

T="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/sysbin"
for b in bash cat dirname grep head; do
	ln -s "$(command -v "$b")" "$T/sysbin/$b"
done

cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == --version ]] || exit 1
[[ ${CURL_OK:-0} == 1 ]] || exit 1
printf 'curl 9.9.9 (fixture)\n'
EOF
chmod +x "$T/bin/curl"

run_report() {
	RC=0
	env PATH="$T/bin:$T/sysbin" CURL_OK="$1" \
		bash "$SRC" >"$T/out" 2>"$T/err" || RC=$?
}

# 1. A tool that cannot report a version is MISSING; the report still exits 0.
run_report 0
if [[ $RC -eq 0 ]] && grep -Fxq '| curl | MISSING |' "$T/out"; then
	pass 'missing tool is reported as MISSING with a zero exit'
else
	fail "missing tool (rc=$RC out=$(grep -F '| curl |' "$T/out"))"
fi

# 2. The same row shows the version when the tool answers.
run_report 1
if [[ $RC -eq 0 ]] && grep -Fxq '| curl | curl 9.9.9 (fixture) |' "$T/out"; then
	pass 'reporting a present tool is unchanged'
else
	fail "present tool (rc=$RC out=$(grep -F '| curl |' "$T/out"))"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all versions report tests passed\n'
