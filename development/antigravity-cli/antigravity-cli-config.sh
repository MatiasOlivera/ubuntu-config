#!/usr/bin/env bash

configure_antigravity_cli() {
    # to use the 'agy' CLI globally
    echo 'export PATH="/home/matias/.local/bin:$PATH"' >>~/.zshrc && source ~/.zshrc
}
