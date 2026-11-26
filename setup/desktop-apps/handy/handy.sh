#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../../helpers/dispatcher.sh"

HANDY_VERSION="0.10.2"
# cjpais/Handy v0.10.2 src-tauri/tauri.conf.json → plugins.updater.pubkey.
HANDY_PUBKEY_B64='dW50cnVzdGVkIGNvbW1lbnQ6IG1pbmlzaWduIHB1YmxpYyBrZXk6IEJBQjcyMDk1MjA2NjAxRjkKUldUNUFXWWdsU0MzdXRRZi8zYzhqV2FaNUVDbDd2Rk5VM1IvWWowVXdmRFNKQ1BrMXF5RFFsLy8K'

install_handy() {
	local installed_ver
	if installed_ver="$(handy_version 2>/dev/null)"; then
		printf 'skip: handy already installed (%s)\n' "$installed_ver"
		return 0
	fi
	handy_dependencies || return 1
	local tmp rc
	tmp="$(mktemp -d)" || return 1
	(handy_install_verified "$tmp")
	rc=$?
	rm -rf -- "$tmp"
	return "$rc"
}

handy_dependencies() {
	sudo apt install -y minisign
}

# Verify the publisher's minisign signature before installing the matching
# release .deb. Nothing unverified reaches apt.
handy_install_verified() {
	local tmp=$1 arch asset base deb sig_b64 sig pub
	case "$(uname -m)" in
	x86_64 | amd64) arch=amd64 ;;
	aarch64 | arm64) arch=arm64 ;;
	*)
		printf 'error: handy: unsupported architecture: %s\n' "$(uname -m)" >&2
		return 1
		;;
	esac
	asset="Handy_${HANDY_VERSION}_${arch}.deb"
	base="https://github.com/cjpais/Handy/releases/download/v${HANDY_VERSION}"
	deb="$tmp/$asset"
	sig_b64="$tmp/$asset.sig.b64"
	sig="$tmp/$asset.minisig"
	pub="$tmp/handy.pub"

	printf '%s\n' "$HANDY_PUBKEY_B64" | base64 -d >"$pub" || {
		printf 'error: handy: cannot decode publisher public key\n' >&2
		return 1
	}
	curl -fsSL --retry 3 "$base/$asset" -o "$deb" || {
		printf 'error: handy: cannot download %s\n' "$asset" >&2
		return 1
	}
	curl -fsSL --retry 3 "$base/$asset.sig" -o "$sig_b64" || {
		printf 'error: handy: cannot download signature for %s\n' "$asset" >&2
		return 1
	}
	base64 -d "$sig_b64" >"$sig" || {
		printf 'error: handy: cannot decode signature for %s\n' "$asset" >&2
		return 1
	}
	minisign -Vm "$deb" -p "$pub" -x "$sig" || {
		printf 'error: handy: signature mismatch for %s\n' "$asset" >&2
		return 1
	}
	sudo apt install -y "$deb"
}

handy_version() {
	dpkg -s handy 2>/dev/null | grep "^Version:"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
