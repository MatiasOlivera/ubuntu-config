#!/usr/bin/env bash

install_zsh() {
    local installed_ver
    if installed_ver="$(zsh_version 2>/dev/null)"; then
        printf 'skip: zsh already installed (%s)\n' "$installed_ver"
        return 0
    fi
    sudo apt install -y zsh
}

zsh_version() {
    zsh --version 2>/dev/null | head -n 1 | grep .
}
