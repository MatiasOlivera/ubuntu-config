#!/usr/bin/env bash

config_fnm() {
    # fnm binary dir is rc-file-only by default; needed for non-interactive shells
    export PATH="$HOME/.local/share/fnm:$PATH"
    fnm install 24
    fnm default 24
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    config_fnm
fi
