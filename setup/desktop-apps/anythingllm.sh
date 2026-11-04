#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

ANYTHINGLLM_REPO='Mintplex-Labs/anything-llm'
ANYTHINGLLM_APP='AnythingLLMDesktop.AppImage'
ANYTHINGLLM_INSTALL_DIR="${ANYTHING_LLM_INSTALL_DIR:-$HOME/Applications}"
ANYTHINGLLM_VERSION_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-config/anythingllm.version"

install_anythingllm() {
	local installed_ver
	if installed_ver="$(anythingllm_version 2>/dev/null)"; then
		printf 'skip: anythingllm already installed (%s)\n' "$installed_ver"
	else
		anythingllm_install_appimage || return 1
	fi
	anythingllm_apparmor_profile
	anythingllm_desktop_entry
}

anythingllm_version() {
	[[ -x $ANYTHINGLLM_INSTALL_DIR/$ANYTHINGLLM_APP && -r $ANYTHINGLLM_VERSION_FILE ]] || return 1
	head -n 1 "$ANYTHINGLLM_VERSION_FILE" | grep .
}

# Prints "<tag>\t<sha256>" for one release asset, from the metadata GitHub
# publishes for it. Fails closed when the release or the digest is absent, so a
# missing integrity record is an error instead of an unverified install.
anythingllm_release_meta() {
	local asset=$1
	command -v curl >/dev/null 2>&1 || return 1
	command -v python3 >/dev/null 2>&1 || return 1
	curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' \
		"https://api.github.com/repos/$ANYTHINGLLM_REPO/releases/latest" |
		python3 -c '
import json, sys
try:
    release = json.load(sys.stdin)
    tag = release["tag_name"]
    for asset in release.get("assets", []):
        if asset.get("name") != sys.argv[1]:
            continue
        digest = (asset.get("digest") or "").split(":", 1)
        if digest[0] != "sha256" or not digest[1]:
            sys.exit(1)
        print("%s\t%s" % (tag, digest[1]))
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
' "$asset"
}

anythingllm_install_appimage() {
	local asset meta tag digest dir part
	case "$(uname -m)" in
	x86_64 | amd64) asset=$ANYTHINGLLM_APP ;;
	aarch64 | arm64) asset=AnythingLLMDesktop-Arm64.AppImage ;;
	*)
		printf 'error: anythingllm: unsupported architecture: %s\n' "$(uname -m)" >&2
		return 1
		;;
	esac
	dir=$ANYTHINGLLM_INSTALL_DIR
	part=$dir/$ANYTHINGLLM_APP.part
	mkdir -p "$dir" || return 1
	if ! meta="$(anythingllm_release_meta "$asset")"; then
		printf 'error: anythingllm: no published sha256 for %s\n' "$asset" >&2
		return 1
	fi
	IFS=$'\t' read -r tag digest <<<"$meta"
	# The tag from the same response as the digest: resolving "latest" twice
	# could straddle a release published mid-run and fail the check misleadingly.
	if ! curl -fsSL --retry 3 \
		"https://github.com/$ANYTHINGLLM_REPO/releases/download/$tag/$asset" -o "$part"; then
		printf 'error: anythingllm: download failed for %s (%s)\n' "$asset" "$tag" >&2
		rm -f "$part"
		return 1
	fi
	if ! printf '%s  %s\n' "$digest" "$part" | sha256sum --status --check -; then
		printf 'error: anythingllm: sha256 mismatch for %s (%s)\n' "$asset" "$tag" >&2
		rm -f "$part"
		return 1
	fi
	chmod +x "$part"
	mv -f "$part" "$dir/$ANYTHINGLLM_APP" || return 1
	mkdir -p "$(dirname "$ANYTHINGLLM_VERSION_FILE")" || return 1
	printf '%s\n' "${tag#v}" >"$ANYTHINGLLM_VERSION_FILE"
}

# Electron's SUID sandbox aborts boot without an unconfined profile. Profile
# syntax follows the apparmor_parser major version, as upstream's installer does.
anythingllm_apparmor_profile() {
	local profile=/etc/apparmor.d/anythingllmdesktop major tmp
	if [[ ! -f /sys/kernel/security/apparmor/profiles ]]; then
		printf 'skip: apparmor not detected (create %s if the AppImage fails on SUID)\n' "$profile"
		return 0
	fi
	[[ -f $profile ]] && return 0
	if ! command -v apparmor_parser >/dev/null 2>&1; then
		printf 'warn: apparmor_parser missing; create %s before first run\n' "$profile"
		return 0
	fi
	major="$(apparmor_parser --version 2>/dev/null | grep -oE '[0-9]+' | head -n 1)"
	tmp="$(mktemp)" || return 0
	if [[ ${major:-0} -ge 4 ]]; then
		cat >"$tmp" <<'EOF'
# AnythingLLMDesktop AppArmor profile (4.x syntax)
abi <abi/4.0>,
include <tunables/global>

profile anythingllmdesktop /**/AnythingLLMDesktop.AppImage flags=(unconfined) {
  userns,
}
EOF
	else
		cat >"$tmp" <<'EOF'
# AnythingLLMDesktop AppArmor profile (classic syntax)
#include <tunables/global>

profile anythingllmdesktop /**/AnythingLLMDesktop.AppImage flags=(unconfined) {
}
EOF
	fi
	if ! sudo install -m 0644 "$tmp" "$profile"; then
		rm -f "$tmp"
		return 0
	fi
	rm -f "$tmp"
	sudo apparmor_parser -r "$profile" ||
		printf 'warn: profile written but not loaded: sudo apparmor_parser -r %s\n' "$profile"
	return 0
}

anythingllm_desktop_entry() {
	local entry="$HOME/.local/share/applications/anythingllmdesktop.desktop"
	[[ -f $entry ]] && return 0
	mkdir -p "$(dirname "$entry")" || return 0
	cat >"$entry" <<EOF
[Desktop Entry]
StartupWMClass=anythingllm-desktop
Type=Application
Name=AnythingLLM Desktop
Exec=$ANYTHINGLLM_INSTALL_DIR/$ANYTHINGLLM_APP
Icon=$HOME/.config/anythingllm-desktop/storage/icon.png
Categories=Utility;
EOF
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
