#!/usr/bin/env bash

install_opencode() {
    local installed_ver
    if installed_ver="$(opencode_version 2>/dev/null)"; then
        printf 'skip: opencode already installed (%s)\n' "$installed_ver"
        return 0
    fi
    curl -fsSL https://opencode.ai/install | bash
}

opencode_version() {
    opencode --version 2>/dev/null | head -n 1 | grep .
}
