#!/usr/bin/env bash

config_handy() {
    local installed_ver
    if installed_ver="$(handy_config_version 2>/dev/null)"; then
        printf 'skip: ydotool already installed (%s)\n' "$installed_ver"
    else
        sudo apt install -y ydotool
    fi
    sudo usermod -aG input "$USER"
    systemctl --user enable --now ydotool
}

handy_config_version() {
    command -v ydotool
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    config_handy
fi