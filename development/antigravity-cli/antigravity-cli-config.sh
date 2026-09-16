#!/usr/bin/env bash

config_antigravity_cli() {
    # to use the 'agy' CLI globally
    echo "export PATH=\"$HOME/.local/bin:\$PATH\"" >>~/.zshrc
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    config_antigravity_cli
fi
