#!/usr/bin/env bash

install_fsearch() {
	sudo add-apt-repository ppa:christian-boxdoerfer/fsearch-daily
	sudo apt update
	sudo apt install -y fsearch
}