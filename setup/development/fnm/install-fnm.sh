#!/usr/bin/env bash

install_fnm() {
    # upstream installer requires unzip (aborts without it)
    sudo apt install -y unzip
    curl -o- https://fnm.vercel.app/install | bash
}
