#!/usr/bin/env bash

install_zoxide() {
    local installed_ver
    if installed_ver="$(zoxide_version 2>/dev/null)"; then
        printf 'skip: zoxide already installed (%s)\n' "$installed_ver"
        return 0
    fi
    sudo apt install -y zoxide
}

zoxide_version() {
    zoxide --version 2>/dev/null | head -n 1 | grep .
}
