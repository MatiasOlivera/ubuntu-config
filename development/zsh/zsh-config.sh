#!/usr/bin/env bash

configure_zsh() {
    # make zsh the default shell
	chsh -s "$(which zsh)"
}