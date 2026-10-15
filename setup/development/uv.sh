#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_uv() {
    local installed_ver
    if installed_ver="$(uv_version 2>/dev/null)"; then
        printf 'skip: uv already installed (%s)\n' "$installed_ver"
        return 0
    fi
    local tmp rc
    tmp="$(mktemp)" || return 1
    if ! curl -LsSf https://astral.sh/uv/install.sh -o "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    if sh "$tmp"; then
        rc=0
    else
        rc=$?
    fi
    rm -f "$tmp"
    return "$rc"
}

# ~/.local/bin is rc-file-only on PATH, and install.sh runs as plain
# non-login bash: without this PATH prepend the skip-guard re-installs on
# every re-run and the report prints MISSING for an installed uv.
# Subshell keeps the caller's environment untouched (report stays read-only).
uv_version() {
    ( PATH="$HOME/.local/bin:$PATH"; uv --version 2>/dev/null | head -n 1 | grep . )
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
