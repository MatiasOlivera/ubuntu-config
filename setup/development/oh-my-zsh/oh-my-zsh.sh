#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../../helpers/dispatcher.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../helpers/remote-installer.sh"

install_oh_my_zsh() {
    local installed_ver
    if installed_ver="$(oh_my_zsh_version 2>/dev/null)"; then
        printf 'skip: oh-my-zsh already installed (%s)\n' "$installed_ver"
        return 0
    fi
    remote_install https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh sh --keep-zshrc --unattended
}

oh_my_zsh_version() {
    [ -d "$HOME/.oh-my-zsh" ] && echo present
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
