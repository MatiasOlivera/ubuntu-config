#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_postman() {
    local installed_ver
    if installed_ver="$(postman_version 2>/dev/null)"; then
        printf 'skip: postman already installed (%s)\n' "$installed_ver"
        return 0
    fi
    sudo flatpak install flathub -y com.getpostman.Postman
}

postman_version() {
    flatpak info com.getpostman.Postman 2>/dev/null | grep -i "Version:" | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
