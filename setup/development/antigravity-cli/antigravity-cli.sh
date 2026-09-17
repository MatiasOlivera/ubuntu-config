#!/usr/bin/env bash

install_antigravity_cli() {
    curl -fsSL https://antigravity.google/cli/install.sh | bash
    # ~/.local/bin is rc-file-only; symlink so agy works in non-interactive shells
    sudo ln -sf "$HOME/.local/bin/agy" /usr/local/bin/agy
}
