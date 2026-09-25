#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../../helpers/dispatcher.sh"

install_oh_my_zsh() {
    local installed_ver
    if installed_ver="$(oh_my_zsh_version 2>/dev/null)"; then
        printf 'skip: oh-my-zsh already installed (%s)\n' "$installed_ver"
        return 0
    fi
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

oh_my_zsh_version() {
    [ -d "$HOME/.oh-my-zsh" ] && echo present
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
