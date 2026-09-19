#!/usr/bin/env bash

install_handy() {
	local ver="0.9.7"
	curl -fsSLO "https://github.com/cjpais/Handy/releases/download/v${ver}/Handy_${ver}_amd64.deb"
	sudo apt install -y "./Handy_${ver}_amd64.deb"
	rm -f "Handy_${ver}_amd64.deb"
}
