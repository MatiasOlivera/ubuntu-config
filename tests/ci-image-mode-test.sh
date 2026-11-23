#!/usr/bin/env bash
# Covers the published-image vs local-build choice used by the CI gate.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

source "$ROOT/tests/ci-image-mode.sh"

check() {
	local expected=$1 actual=$2 label=$3
	if [[ $actual != "$expected" ]]; then
		printf 'expected %s, got %s (%s)\n' "$expected" "$actual" "$label" >&2
		exit 1
	fi
}

mkdir -p "$T/bin"
cat > "$T/bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GIT_CALLS"
if [[ $1 == diff && -n ${TEST_DIFF:-} && " $* " == *" $TEST_DIFF "* ]]; then
	printf '%s\n' "$TEST_DIFF"
fi
EOF
chmod +x "$T/bin/git"
export PATH="$T/bin:$PATH"
export GIT_CALLS="$T/git-calls"
export TEST_DIFF=""

check pull "$(ci_image_mode develop)" "no image change"

TEST_DIFF="tests/Dockerfile"
check build "$(ci_image_mode develop)" "Dockerfile change"

TEST_DIFF="tests/compose.yml"
check build "$(ci_image_mode develop)" "compose change"

TEST_DIFF="setup/install.sh"
check pull "$(ci_image_mode develop)" "unrelated change"

check pull "$(ci_image_mode '')" "no base ref"

# A failed fetch must fail closed instead of falling back to a stale image.
cat > "$T/bin/git" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$T/bin/git"
if ci_image_mode develop >/dev/null 2>&1; then
	printf 'expected failure when git fetch fails\n' >&2
	exit 1
fi

printf 'ok: ci-image-mode\n'
