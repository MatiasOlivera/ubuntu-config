#!/usr/bin/env bash

fnm_dependencies() {
    sudo apt install -y unzip
}

install_fnm() {
    local installed_ver
    if installed_ver="$(fnm_version 2>/dev/null)"; then
        printf 'skip: fnm already installed (%s)\n' "$installed_ver"
        return 0
    fi
    fnm_dependencies
    curl -o- https://fnm.vercel.app/install | bash
}

fnm_version() {
    export PATH="$HOME/.local/share/fnm:$PATH"
    fnm --version 2>/dev/null | head -n 1 | grep .
}
