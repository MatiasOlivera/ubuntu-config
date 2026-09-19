#!/usr/bin/env bash

install_beekeeper_studio_repository() {
    # Instalar nuestra clave GPG
    curl -fsSL https://deb.beekeeperstudio.io/beekeeper.key | sudo gpg --dearmor --output /usr/share/keyrings/beekeeper.gpg &&
        sudo chmod go+r /usr/share/keyrings/beekeeper.gpg &&
        echo "deb [signed-by=/usr/share/keyrings/beekeeper.gpg] https://deb.beekeeperstudio.io stable main" |
        sudo tee /etc/apt/sources.list.d/beekeeper-studio-app.list >/dev/null
}

install_beekeeper_studio() {
    sudo apt install beekeeper-studio -y
}
