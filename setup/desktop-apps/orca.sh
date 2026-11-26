#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

ORCA_VERSION="1.4.206"
# GitHub release-asset SHA-256 digest for orca-ide_${ORCA_VERSION}_amd64.deb.
# The maintainer publishes no checksum or signature for desktop .deb releases,
# so ADR 0007's GitHub-digest fallback applies.
ORCA_SHA256="66e6ea0ca2aaeb706297d27bf7d6ecb8c352737954e4d527c6a66e0b1518b956"

install_orca() {
	local installed_ver
	if installed_ver="$(orca_version 2>/dev/null)"; then
		printf 'skip: orca already installed (%s)\n' "$installed_ver"
		return 0
	fi
	local tmp rc
	tmp="$(mktemp -d)" || return 1
	(orca_install_verified "$tmp")
	rc=$?
	rm -rf -- "$tmp"
	return "$rc"
}

orca_install_verified() {
	local tmp=$1 asset base deb
	asset="orca-ide_${ORCA_VERSION}_amd64.deb"
	base="https://github.com/stablyai/orca/releases/download/v${ORCA_VERSION}"
	deb="$tmp/$asset"
	curl -fsSL "$base/$asset" -o "$deb" || {
		printf 'error: orca: cannot download %s\n' "$asset" >&2
		return 1
	}
	if ! printf '%s  %s\n' "$ORCA_SHA256" "$deb" | sha256sum --check --status -; then
		printf 'error: orca: checksum mismatch for %s\n' "$asset" >&2
		return 1
	fi
	sudo apt install -y "$deb"
}

orca_version() {
	dpkg -s orca-ide 2>/dev/null | grep "^Version:"
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
