#! /bin/bash

install_fuse() {
    local installed_ver
    if installed_ver="$(fuse_version 2>/dev/null)"; then
        printf 'skip: fuse already installed (%s)\n' "$installed_ver"
        return 0
    fi
    # allows to execute AppImages
    sudo apt install -y libfuse2t64
}

fuse_version() {
    dpkg -s libfuse2t64 2>/dev/null | grep "^Version:"
}
