#!/usr/bin/env bash

config_zsh() {
    # make zsh the default shell
	chsh -s "$(which zsh)"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	config_zsh
fi