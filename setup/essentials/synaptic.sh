#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_synaptic() {
    local installed_ver
    if installed_ver="$(synaptic_version 2>/dev/null)"; then
        printf 'skip: synaptic already installed (%s)\n' "$installed_ver"
        return 0
    fi
    sudo apt install -y synaptic
}

synaptic_version() {
    dpkg -s synaptic 2>/dev/null | grep "^Version:"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
