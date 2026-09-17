#!/usr/bin/env bash
#
# test.sh — static + source-only by default, Multipass e2e with --vm.
# Fail-closed: any failure exits 1.

UBUNTU_IMAGE="26.04"
VM_NAME="ubuntu-config-test"

RUN_VM=0
KEEP=0
REUSE=0

usage() {
	printf 'Usage: %s [--vm [--keep] [--reuse]]\n' "$0" >&2
}

while [[ $# -gt 0 ]]; do
	case $1 in
	--vm) RUN_VM=1 ;;
	--keep) KEEP=1 ;;
	--reuse) REUSE=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		usage
		exit 1
		;;
	esac
	shift
done

if [[ $KEEP -eq 1 && $RUN_VM -eq 0 ]]; then
	usage
	exit 1
fi

if [[ $REUSE -eq 1 && $RUN_VM -eq 0 ]]; then
	usage
	exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETUP_DIR="$ROOT/setup"
FAILURES=0

printf 'versions: bash=%s shellcheck=%s multipass=%s\n' \
	"$BASH_VERSION" \
	"$(command -v shellcheck >/dev/null 2>&1 && shellcheck --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || echo missing)" \
	"$(command -v multipass >/dev/null 2>&1 && multipass version | head -n 1 || echo missing)"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

pass() {
	printf 'ok: %s\n' "$1"
}

mapfile -t ALL_SCRIPTS < <(find "$SETUP_DIR" -name '*.sh' -not -path "$ROOT/.git/*" | sort)

# 1. syntax: bash -n over every script
for f in "${ALL_SCRIPTS[@]}"; do
	if bash -n "$f"; then
		pass "bash -n $f"
	else
		fail "bash -n $f"
	fi
done

# 2. every library script is sourced by install.sh or post-install.sh.
for f in "${ALL_SCRIPTS[@]}"; do
	case "$f" in
	"$SETUP_DIR/install.sh" | "$SETUP_DIR/post-install.sh") continue ;;
	esac
	if grep -qF "$(basename "$f")" "$SETUP_DIR/install.sh" "$SETUP_DIR/post-install.sh"; then
		pass "sourced $f"
	else
		fail "not sourced: $f"
	fi
done

# 3. source-only: each library script defines >=1 install_*/config_*
# function when sourced. Functions are never called. install.sh and
# post-install.sh are never sourced (post-install.sh runs apt upgrade).
for f in "${ALL_SCRIPTS[@]}"; do
	case "$f" in
	"$SETUP_DIR/install.sh" | "$SETUP_DIR/post-install.sh") continue ;;
	esac
	if funcs="$(bash -c 'source "$1" && declare -F' _ "$f" 2>/dev/null)" &&
		printf '%s\n' "$funcs" | grep -qE 'declare -f (install_|config_)'; then
		pass "source-only $f"
	else
		fail "source-only $f (no install_*/config_* function found)"
	fi
done

# 4. every *config*.sh works standalone (BASH_SOURCE guard per AGENTS.md)
while IFS= read -r f; do
	if grep -q 'BASH_SOURCE' "$f"; then
		pass "standalone guard $f"
	else
		fail "standalone guard missing in $f"
	fi
done < <(find "$SETUP_DIR" -name '*config*.sh' -not -path "$ROOT/.git/*" | sort)

# 5. shellcheck if installed, else skip (keeps zero-dep default)
if command -v shellcheck >/dev/null 2>&1; then
	# SC1091 (can't follow $VAR sources) excluded: check 2 verifies targets exist.
	if shellcheck -e SC1091 "${ALL_SCRIPTS[@]}"; then
		pass "shellcheck"
	else
		fail "shellcheck"
	fi
else
	printf 'skip: shellcheck (not installed)\n'
fi

# Phase 2 — Multipass e2e on a fresh Ubuntu VM (only with --vm).
# Skipped when Phase 1 failed: never boot a VM on a broken tree.
if [[ $RUN_VM -eq 1 && $FAILURES -eq 0 ]]; then
	if ! command -v multipass >/dev/null 2>&1; then
		fail "multipass not installed"
	else
		trap '[[ $KEEP -eq 0 ]] && multipass delete -p "$VM_NAME" >/dev/null 2>&1 || true' EXIT

		if [[ $REUSE -eq 1 ]] && multipass list 2>/dev/null | grep -qw "$VM_NAME"; then
			multipass start "$VM_NAME" >/dev/null 2>&1 || true
			pass "reuse VM $VM_NAME (skip launch)"
		else
			if multipass list 2>/dev/null | grep -qw "$VM_NAME"; then
				multipass delete -p "$VM_NAME" || fail "delete stale VM $VM_NAME"
			fi

			if multipass launch "$UBUNTU_IMAGE" --name "$VM_NAME" --cpus 2 --memory 4G --disk 20G; then
				pass "multipass launch $UBUNTU_IMAGE"
			else
				fail "multipass launch $UBUNTU_IMAGE"
			fi
		fi

		tarball="$(mktemp "$HOME/ubuntu-config-test.XXXXXX.tar.gz")"
		if tar -czf "$tarball" --exclude=.git -C "$ROOT" . &&
			multipass transfer "$tarball" "$VM_NAME:/home/ubuntu/ubuntu-config.tar.gz" &&
			multipass exec "$VM_NAME" -- mkdir -p /home/ubuntu/ubuntu-config &&
			multipass exec "$VM_NAME" -- tar -xzf /home/ubuntu/ubuntu-config.tar.gz -C /home/ubuntu/ubuntu-config; then
			pass "transfer repo to VM"
		else
			fail "transfer repo to VM"
		fi
		rm -f "$tarball"

		if multipass exec "$VM_NAME" -- env CHEZMOI_NAME="Test" CHEZMOI_EMAIL="test@example.com" bash /home/ubuntu/ubuntu-config/setup/install.sh; then
			pass "install.sh in VM"
		else
			fail "install.sh in VM"
		fi

		if multipass exec "$VM_NAME" -- env SKIP_UPGRADE=1 bash /home/ubuntu/ubuntu-config/setup/post-install.sh; then
			pass "post-install.sh in VM"
		else
			fail "post-install.sh in VM"
		fi

		if multipass exec "$VM_NAME" -- which git docker zsh curl; then
			pass "smoke: git docker zsh curl in VM"
		else
			fail "smoke: git docker zsh curl in VM"
		fi

		if [[ $KEEP -eq 1 ]]; then
			printf 'keeping VM %s running for inspection\n' "$VM_NAME"
		fi
	fi
elif [[ $RUN_VM -eq 1 ]]; then
	printf 'skip: Multipass e2e (Phase 1 failed)\n'
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all checks passed\n'
