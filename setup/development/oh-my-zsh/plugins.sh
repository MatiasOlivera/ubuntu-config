#!/usr/bin/env bash

install_oh_my_zsh_plugins() {
    local base="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
    local installed_ver
    if installed_ver="$(oh_my_zsh_plugins_version 2>/dev/null)"; then
        printf 'skip: oh-my-zsh plugins already installed (%s)\n' "$installed_ver"
        return 0
    fi
    # zsh-autosuggestions
    [ -d "$base/zsh-autosuggestions" ] || git clone https://github.com/zsh-users/zsh-autosuggestions "$base/zsh-autosuggestions"

    # zsh-syntax-highlighting
    [ -d "$base/zsh-syntax-highlighting" ] || git clone https://github.com/zsh-users/zsh-syntax-highlighting "$base/zsh-syntax-highlighting"
}

oh_my_zsh_plugins_version() {
    [ -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ] && [ -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ] && echo present
}
