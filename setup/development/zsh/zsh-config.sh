#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../../helpers/dispatcher.sh"

config_zsh() {
    # make zsh the default shell
	sudo chsh -s "$(which zsh)" "$(id -un)"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
