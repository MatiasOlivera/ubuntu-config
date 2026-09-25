#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_ollama() {
    local installed_ver
    if installed_ver="$(ollama_version 2>/dev/null)"; then
        printf 'skip: ollama already installed (%s)\n' "$installed_ver"
        return 0
    fi
    curl -fsSL https://ollama.com/install.sh | sh
}

ollama_version() {
    ollama --version 2>/dev/null | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
