#!/usr/bin/env bash

config_fnm() {
    fnm install 24
    fnm default 24
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    config_fnm
fi
