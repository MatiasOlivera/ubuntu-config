#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../../helpers/dispatcher.sh"

config_fnm() {
    # fnm binary dir is rc-file-only by default; needed for non-interactive shells
    export PATH="$HOME/.local/share/fnm:$PATH"
    fnm install 24
    fnm default 24
}

node_version() {
    node --version 2>/dev/null | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    dispatch_command "$@"
fi
