#!/usr/bin/env bash

homebrew_dependencies() {
    sudo apt install -y build-essential procps curl file git
}

install_homebrew() {
    local installed_ver
    if installed_ver="$(brew_version 2>/dev/null)"; then
        printf 'skip: homebrew already installed (%s)\n' "$installed_ver"
        return 0
    fi
    homebrew_dependencies
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

brew_version() {
    export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"
    brew --version 2>/dev/null | head -n 1 | grep .
}
