#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_bitwarden_cli() {
    local installed_ver
    if installed_ver="$(bitwarden_cli_version 2>/dev/null)"; then
        printf 'skip: bitwarden-cli already installed (%s)\n' "$installed_ver"
        return 0
    fi
    sudo snap install bw
}

bitwarden_cli_version() {
    snap list bw 2>/dev/null | tail -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
