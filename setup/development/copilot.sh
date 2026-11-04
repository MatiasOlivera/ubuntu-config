#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_copilot() {
    local installed_ver
    if installed_ver="$(copilot_version 2>/dev/null)"; then
        printf 'skip: copilot already installed (%s)\n' "$installed_ver"
        return 0
    fi
    local tmp rc
    tmp="$(mktemp)" || return 1
    if ! curl -fsSL https://gh.io/copilot-install -o "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    if bash "$tmp"; then
        rc=0
    else
        rc=$?
    fi
    rm -f "$tmp"
    return "$rc"
}

copilot_version() {
    copilot --version 2>/dev/null | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
