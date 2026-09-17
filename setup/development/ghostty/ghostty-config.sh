#!/usr/bin/env bash

config_ghostty() {
    # Set ghostty as the default terminal emulator
    # Open with shortcut `Ctrl + Alt + T`
    gsettings set org.gnome.desktop.default-applications.terminal exec 'ghostty'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    config_ghostty
fi