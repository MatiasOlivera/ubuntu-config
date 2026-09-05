#!/usr/bin/env bash

# @brief Installs fnm and sets up the default Node.js version.
# @description Fast Node Manager (fnm) is a simple, fast and cross-platform Node.js version manager, written in Rust. It allows you to easily install and manage multiple versions of Node.js on your system.
#
# @see [fnm](https://github.com/schniz/fnm)
# @see [Node.js](https://nodejs.org/en/download)
install_fnm() {
    # Download and install fnm
    curl -o- https://fnm.vercel.app/install | bash

    # Restart your shell:
    exec zsh

    # Download and install Node.js
    fnm install 24

    # Set the default Node.js version
    fnm default 24
}
