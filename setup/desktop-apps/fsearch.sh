#!/usr/bin/env bash

install_fsearch() {
	local installed_ver
	if installed_ver="$(fsearch_version 2>/dev/null)"; then
		printf 'skip: fsearch already installed (%s)\n' "$installed_ver"
		return 0
	fi
	sudo apt install -y fsearch
}

install_fsearch_repository() {
	# Manual entry: add-apt-repository calls api.launchpad.net, which
	# stalls ~2 min per run here. Key fingerprint per
	# https://launchpad.net/~christian-boxdoerfer/+archive/ubuntu/fsearch-stable
	curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x75555AFF5215AD9DBFD8CDB952B2FFB2DC496F40" | sudo gpg --dearmor -o /usr/share/keyrings/fsearch.gpg
	sudo tee /etc/apt/sources.list.d/fsearch.sources >/dev/null <<EOF
Types: deb
URIs: https://ppa.launchpadcontent.net/christian-boxdoerfer/fsearch-stable/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: main
Signed-By: /usr/share/keyrings/fsearch.gpg
EOF
}

fsearch_version() {
	dpkg -s fsearch 2>/dev/null | grep "^Version:"
}
