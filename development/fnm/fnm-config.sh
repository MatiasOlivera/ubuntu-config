#!/usr/bin/env bash

configure_fnm() {
    fnm install 24
    fnm default 24
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    configure_fnm
fi
