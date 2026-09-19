#!/usr/bin/env bash

install_fnm() {
    local installed_ver
    if installed_ver="$(fnm_version 2>/dev/null)"; then
        printf 'skip: fnm already installed (%s)\n' "$installed_ver"
        return 0
    fi
    # upstream installer requires unzip (aborts without it)
    sudo apt install -y unzip
    curl -o- https://fnm.vercel.app/install | bash
}

fnm_version() {
    export PATH="$HOME/.local/share/fnm:$PATH"
    fnm --version 2>/dev/null | head -n 1 | grep .
}
