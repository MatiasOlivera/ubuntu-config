#!/usr/bin/env bash

install_docker() {
    local installed_ver
    if installed_ver="$(docker_version 2>/dev/null)" && docker_compose_version >/dev/null 2>&1; then
        printf 'skip: docker already installed (%s)\n' "$installed_ver"
    else
        # Install the Docker packages.
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo apt install -y util-linux-extra
    fi

    # Post installation
    # https://docs.docker.com/engine/install/linux-postinstall/

    # Manage Docker as a non-root user
    sudo groupadd -f docker
    sudo usermod -aG docker "$USER"

    newgrp docker
}

install_docker_repository() {
    # https://docs.docker.com/engine/install/ubuntu/
    # Set up Docker's apt repository (sources only, no apt update here).

    # Add Docker's official GPG key:
    sudo apt install -y ca-certificates curl
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
}

docker_version() {
    docker --version 2>/dev/null | head -n 1 | grep .
}

docker_compose_version() {
    docker compose version 2>/dev/null | head -n 1 | grep .
}
