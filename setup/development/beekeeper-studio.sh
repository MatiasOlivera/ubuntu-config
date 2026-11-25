#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/apt-source.sh"

install_beekeeper_studio() {
    local installed_ver
    if installed_ver="$(beekeeper_studio_version 2>/dev/null)"; then
        printf 'skip: beekeeper-studio already installed (%s)\n' "$installed_ver"
        return 0
    fi
    sudo apt install beekeeper-studio -y
}

install_beekeeper_studio_repository() {
    curl -fsSL https://deb.beekeeperstudio.io/beekeeper.key | sudo gpg --dearmor --yes --output /usr/share/keyrings/beekeeper.gpg &&
        sudo chmod go+r /usr/share/keyrings/beekeeper.gpg &&
        echo "deb [signed-by=/usr/share/keyrings/beekeeper.gpg] https://deb.beekeeperstudio.io stable main" |
        apt_source_write beekeeper-studio-app.list
}

beekeeper_studio_version() {
    dpkg -s beekeeper-studio 2>/dev/null | grep "^Version:"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
