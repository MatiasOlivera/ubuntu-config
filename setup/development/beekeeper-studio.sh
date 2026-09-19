#!/usr/bin/env bash

install_beekeeper_studio() {
    local installed_ver
    if installed_ver="$(beekeeper_studio_version 2>/dev/null)"; then
        printf 'skip: beekeeper-studio already installed (%s)\n' "$installed_ver"
        return 0
    fi
    sudo apt install beekeeper-studio -y
}

install_beekeeper_studio_repository() {
    # Instalar nuestra clave GPG
    curl -fsSL https://deb.beekeeperstudio.io/beekeeper.key | sudo gpg --dearmor --output /usr/share/keyrings/beekeeper.gpg &&
        sudo chmod go+r /usr/share/keyrings/beekeeper.gpg &&
        echo "deb [signed-by=/usr/share/keyrings/beekeeper.gpg] https://deb.beekeeperstudio.io stable main" |
        sudo tee /etc/apt/sources.list.d/beekeeper-studio-app.list >/dev/null
}

beekeeper_studio_version() {
    dpkg -s beekeeper-studio 2>/dev/null | grep "^Version:"
}
