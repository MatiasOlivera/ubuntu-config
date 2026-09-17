#!/usr/bin/env bash

config_handy() {
    sudo apt install -y ydotool
    sudo usermod -aG input "$USER"
    systemctl --user enable --now ydotool
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    config_handy
fi