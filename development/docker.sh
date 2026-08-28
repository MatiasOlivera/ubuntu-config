#!/usr/bin/env bash

install_docker() {
    # https://docs.docker.com/engine/install/ubuntu/
    # Set up Docker's apt repository.

    # Add Docker's official GPG key:
    sudo apt update
    sudo apt install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt update

    # Install the Docker packages.
    sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Post installation
    # https://docs.docker.com/engine/install/linux-postinstall/

    # Manage Docker as a non-root user
    sudo groupadd docker
    sudo usermod -aG docker $USER

    sudo apt install util-linux-extra
    newgrp docker
}
