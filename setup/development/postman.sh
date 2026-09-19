#!/usr/bin/env bash

install_postman() {
    local installed_ver
    if installed_ver="$(postman_version 2>/dev/null)"; then
        printf 'skip: postman already installed (%s)\n' "$installed_ver"
        return 0
    fi
    sudo snap install postman
}

postman_version() {
    snap list postman 2>/dev/null | tail -n 1 | grep .
}
