#!/usr/bin/env bash
#
# dev-iter.sh — development-only shortcut: re-run just the setup scripts that
# changed since the last iteration, inside an already configured VM. Not part of
# the full verification; always run ./tests/test.sh --vm --reuse before a PR.
#
#   tests/dev-iter.sh seed   # record the current setup scripts as the baseline
#   tests/dev-iter.sh        # run changed installers in the kept VM

set -uo pipefail

ROOT=${UBUNTU_CONFIG_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
VM_NAME=${VM_NAME:-$(bash "$ROOT/tests/vm-name.sh" "$ROOT")}
MP=${MULTIPASS:-multipass}
STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-config
STATE_FILE=$STATE_DIR/dev-iter-$VM_NAME.sha

setup_files() {
	find "$ROOT/setup" -name '*.sh' -type f \
		-not -path '*/helpers/*' \
		! -name 'install.sh' ! -name 'post-install.sh' |
		sed "s|^$ROOT/||" | sort
}

snapshot() {
	local rel
	while IFS= read -r rel; do
		printf '%s  %s\n' "$(sha256sum "$ROOT/$rel" | awk '{print $1}')" "$rel"
	done < <(setup_files)
}

if [[ ${1:-} == seed ]]; then
	mkdir -p "$STATE_DIR" || exit 1
	snapshot > "$STATE_FILE" || exit 1
	printf 'seeded dev loop for %s with %s scripts\n' "$VM_NAME" "$(wc -l < "$STATE_FILE")"
	exit 0
fi

[[ -f $STATE_FILE ]] || {
	printf 'error: no dev-loop seed for %s; run "%s seed" first\n' "$VM_NAME" "$0" >&2
	exit 1
}

current=$(mktemp) || exit 1
snapshot > "$current" || exit 1
mapfile -t changed < <(awk '
	FNR == NR { old[$2] = $1; next }
	!( $2 in old ) || old[$2] != $1 { print $2 }
' "$STATE_FILE" "$current")

if [[ ${#changed[@]} -eq 0 ]]; then
	rm -f "$current"
	printf 'no changed setup scripts since last iteration\n'
	exit 0
fi

printf 'changed setup scripts:\n'
printf '  %s\n' "${changed[@]}"

tarball=$(mktemp "$HOME/ubuntu-config-dev.XXXXXX.tar.gz") || exit 1
tar -czf "$tarball" --exclude=.git -C "$ROOT" . || exit 1
"$MP" transfer "$tarball" "$VM_NAME:/home/ubuntu/ubuntu-config.tar.gz" || exit 1
"$MP" exec "$VM_NAME" -- mkdir -p /home/ubuntu/ubuntu-config || exit 1
"$MP" exec "$VM_NAME" -- tar -xzf /home/ubuntu/ubuntu-config.tar.gz -C /home/ubuntu/ubuntu-config || exit 1
rm -f "$tarball"

remote='set -e;'
for rel in "${changed[@]}"; do
	if grep -qE 'install_.*_repository\(\)' "$ROOT/$rel"; then
		remote+=" bash /home/ubuntu/ubuntu-config/$rel repository;"
	fi
done
remote+=' sudo apt update >/dev/null;'
for rel in "${changed[@]}"; do
	remote+=" bash /home/ubuntu/ubuntu-config/$rel install;"
	case $rel in
	*config*.sh) remote+=" bash /home/ubuntu/ubuntu-config/$rel config;" ;;
	esac
done
remote+=' which git docker zsh curl >/dev/null'

if "$MP" exec "$VM_NAME" -- env CHEZMOI_NAME=Test CHEZMOI_EMAIL=test@example.com \
	SKIP_UPGRADE=1 bash -c "$remote"; then
	mv "$current" "$STATE_FILE"
	printf 'dev iteration complete; baseline advanced\n'
else
	rm -f "$current"
	exit 1
fi
