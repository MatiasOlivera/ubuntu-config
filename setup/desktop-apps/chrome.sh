#!/usr/bin/env bash

install_chrome() {
	curl -fsSLO https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
	sudo apt install -y ./google-chrome-stable_current_amd64.deb
	rm -f google-chrome-stable_current_amd64.deb
}