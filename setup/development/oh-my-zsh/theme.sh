#!/usr/bin/env bash

install_oh_my_zsh_theme() {
    local installed_ver
    if installed_ver="$(oh_my_zsh_theme_version 2>/dev/null)"; then
        printf 'skip: powerlevel10k already installed (%s)\n' "$installed_ver"
        return 0
    fi
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
}

oh_my_zsh_theme_version() {
    [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ] && echo present
}
