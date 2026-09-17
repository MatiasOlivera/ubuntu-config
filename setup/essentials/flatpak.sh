#!/usr/bin/env bash

install_flatpak() {
	sudo apt install -y flatpak gnome-software-plugin-flatpak
	flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}