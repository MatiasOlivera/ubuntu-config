#!/usr/bin/env bash

install_gitkraken() {
	curl -fsSLO https://release.gitkraken.com/linux/gitkraken-amd64.deb
	sudo apt install -y ./gitkraken-amd64.deb
	rm -f gitkraken-amd64.deb
}
