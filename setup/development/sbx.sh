#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_sbx() {
    local installed_ver
    if installed_ver="$(sbx_version 2>/dev/null)"; then
        printf 'skip: sbx already installed (%s)\n' "$installed_ver"
    else
        # https://docs.docker.com/ai/sandboxes/install/ (Install SBX only;
        # the Docker apt repository is already set up by install_docker_repository).
        sudo apt install -y docker-sbx
    fi

    # Local sandboxes require KVM
    sudo groupadd -f kvm
    sudo usermod -aG kvm "$USER"

    printf 'next: sign in with sbx login (browser OAuth), re-login for the kvm group\n'
}

sbx_version() {
    sbx --version 2>/dev/null | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
