#!/usr/bin/env bash

usage() {
	printf 'Usage: %s "user.name" "user.email"\n' "$0" >&2
}

config_git() {
	local name=$1
	local email=$2

	git config --global user.name "$name"
	git config --global user.email "$email"
	git config --global core.editor code
	git config --global init.defaultBranch main
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	if [[ $# -ne 2 ]]; then
		usage
		exit 1
	fi

	config_git "$1" "$2"
fi