#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_openusage() {
    local installed_ver
    if installed_ver="$(openusage_version 2>/dev/null)"; then
        printf 'skip: openusage already installed (%s)\n' "$installed_ver"
        return 0
    fi
    local tmp
    tmp=$(mktemp)
    if ! curl -fsSL https://github.com/janekbaraniewski/openusage/releases/latest/download/install.sh -o "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    bash "$tmp"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

openusage_version() {
    local v
    if ! v=$(openusage --version 2>/dev/null); then
        return 1
    fi
    printf '%s\n' "$v" | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
