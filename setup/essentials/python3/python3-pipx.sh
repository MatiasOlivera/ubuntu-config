#!/usr/bin/env bash

install_pipx() {
    local installed_ver
    if installed_ver="$(pipx_version 2>/dev/null)"; then
        printf 'skip: pipx already installed (%s)\n' "$installed_ver"
    else
        sudo apt install -y pipx
    fi
    pipx ensurepath
}

pipx_version() {
    pipx --version 2>/dev/null | head -n 1 | grep .
}
