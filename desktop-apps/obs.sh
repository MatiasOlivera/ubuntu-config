#!/usr/bin/env bash

install_obs() {
	flatpak install flathub com.obsproject.Studio
	sudo apt-get install obs-advanced-masks
}