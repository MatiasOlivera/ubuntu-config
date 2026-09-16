#!/usr/bin/env bash

config_antigravity_cli() {
    # to use the 'agy' CLI globally (guarded: upstream installer already appends this)
    grep -qF '.local/bin' ~/.zshrc || echo "export PATH=\"$HOME/.local/bin:\$PATH\"" >>~/.zshrc
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    config_antigravity_cli
fi
