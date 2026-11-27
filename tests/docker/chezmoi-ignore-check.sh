#!/usr/bin/env bash
#
# chezmoi-ignore-check.sh — hermetic check for issue #165.
# Container-only: needs the real chezmoi binary. Uses temp source and
# destination dirs, so no host dotfile, network, or sudo is touched.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILURES=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	printf 'ok: %s\n' "$1"
}

if ! command -v chezmoi >/dev/null 2>&1; then
	printf 'error: chezmoi is required for this check; run it in the container:\n' >&2
	printf '  docker compose -f tests/compose.yml run --rm test bash tests/docker/chezmoi-ignore-check.sh\n' >&2
	exit 1
fi

T="$(mktemp -d)" || {
	printf 'error: mktemp failed, refusing to run\n' >&2
	exit 1
}
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/src/dot_config/app/nested/dot_ssh" "$T/home"

cp "$ROOT/dotfiles/.chezmoiignore" "$T/src/.chezmoiignore"

# Each source path maps to the target path a nested credential would occupy.
# Non-empty content matters: chezmoi skips zero-byte source files on apply.
for source in \
	"$T/src/dot_secret-root" \
	"$T/src/dot_config/app/credentials.json" \
	"$T/src/dot_config/app/nested/token.txt" \
	"$T/src/dot_config/app/nested/dot_env.local" \
	"$T/src/dot_config/app/nested/id_ed25519" \
	"$T/src/dot_config/app/nested/dot_ssh/id_rsa" \
	"$T/src/dot_config/app/settings.json"; do
	printf 'test\n' >"$source"
done

export HOME="$T/home"
export XDG_CONFIG_HOME="$T/home/.config"

ignored="$(chezmoi --source "$T/src" --destination "$T/home" ignored 2>&1)" || {
	fail "chezmoi ignored: $ignored"
	ignored=
}

CREDENTIALS=(
	".secret-root"
	".config/app/credentials.json"
	".config/app/nested/token.txt"
	".config/app/nested/.env.local"
	".config/app/nested/id_ed25519"
	".config/app/nested/.ssh/id_rsa"
)

# chezmoi reports an ignored directory, not the files it contains.
IGNORED_TARGETS=(
	".secret-root"
	".config/app/credentials.json"
	".config/app/nested/token.txt"
	".config/app/nested/.env.local"
	".config/app/nested/id_ed25519"
	".config/app/nested/.ssh"
)

for target in "${IGNORED_TARGETS[@]}"; do
	if grep -Fxq -- "$target" <<<"$ignored"; then
		pass "ignored: $target"
	else
		fail "not ignored: $target"
	fi
done

if grep -Fxq -- '.config/app/settings.json' <<<"$ignored"; then
	fail "benign file was also ignored: .config/app/settings.json"
else
	pass "benign file remains managed: .config/app/settings.json"
fi

if out="$(chezmoi --source "$T/src" --destination "$T/home" apply --force 2>&1)"; then
	pass "chezmoi apply exits 0"
else
	fail "chezmoi apply: $out"
fi

for target in "${CREDENTIALS[@]}"; do
	if [[ -e $T/home/$target ]]; then
		fail "deployed credential file: $target"
	else
		pass "not deployed: $target"
	fi
done

if [[ -f $T/home/.config/app/settings.json ]]; then
	pass "benign file deployed: .config/app/settings.json"
else
	fail "benign file not deployed: .config/app/settings.json"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all checks passed\n'
