#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../../helpers/dispatcher.sh"

install_ghostty() {
    local installed_ver
    if installed_ver="$(ghostty_version 2>/dev/null)"; then
        printf 'skip: ghostty already installed (%s)\n' "$installed_ver"
        return 0
    fi
    sudo apt install -y ghostty
}

ghostty_version() {
    ghostty --version 2>/dev/null | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
