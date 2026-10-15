#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_openusage() {
    local installed_ver
    if installed_ver="$(openusage_version 2>/dev/null)"; then
        printf 'skip: openusage already installed (%s)\n' "$installed_ver"
        return 0
    fi
    curl -fsSL https://github.com/janekbaraniewski/openusage/releases/latest/download/install.sh | bash
}

openusage_version() {
    openusage --version 2>/dev/null | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
