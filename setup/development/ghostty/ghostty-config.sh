#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../../helpers/dispatcher.sh"

config_ghostty() {
    # Set ghostty as the default terminal emulator
    # Open with shortcut `Ctrl + Alt + T`
    gsettings set org.gnome.desktop.default-applications.terminal exec 'ghostty'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
