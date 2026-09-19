#!/usr/bin/env bash

install_antigravity_cli() {
    local installed_ver
    if installed_ver="$(antigravity_cli_version 2>/dev/null)"; then
        printf 'skip: antigravity already installed (%s)\n' "$installed_ver"
    else
        curl -fsSL https://antigravity.google/cli/install.sh | bash
    fi
    # ~/.local/bin is rc-file-only; symlink so agy works in non-interactive shells
    sudo ln -sf "$HOME/.local/bin/agy" /usr/local/bin/agy
}

antigravity_cli_version() {
    agy --version 2>/dev/null | head -n 1 | grep .
}
