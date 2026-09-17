#!/usr/bin/env bash

install_pipx() {
    sudo apt install -y pipx
    pipx ensurepath
}
