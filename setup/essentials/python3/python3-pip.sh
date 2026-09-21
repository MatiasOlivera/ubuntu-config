#!/usr/bin/env bash

install_pip() {
    local installed_ver
    if installed_ver="$(pip_version 2>/dev/null)"; then
        printf 'skip: pip already installed (%s)\n' "$installed_ver"
        return 0
    fi
    sudo apt install -y python3-pip
}

pip_version() {
    pip3 --version 2>/dev/null | head -n 1 | grep .
}
