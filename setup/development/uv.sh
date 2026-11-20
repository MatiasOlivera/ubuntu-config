#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_uv() {
    local installed_ver
    if installed_ver="$(uv_version 2>/dev/null)"; then
        printf 'skip: uv already installed (%s)\n' "$installed_ver"
        return 0
    fi
    local tmp rc
    tmp="$(mktemp -d)" || return 1
    # Subshell keeps this trap-free: install.sh owns the EXIT trap (sudo keepalive).
    (uv_install_verified "$tmp")
    rc=$?
    rm -rf -- "$tmp"
    return "$rc"
}

# Installs the latest Linux release tarball only after checking it against the
# publisher's per-asset .sha256 file. The astral.sh install script is never
# executed: no integrity material is published for the script itself.
uv_install_verified() {
    local tmp=$1 arch asset tag release_json base src bin_dir ver
    local staged_uv staged_uvx cmd metadata_script
    case "$(uname -m)" in
        x86_64 | amd64) arch=x86_64-unknown-linux-gnu ;;
        aarch64 | arm64) arch=aarch64-unknown-linux-gnu ;;
        *) printf 'error: uv: unsupported architecture: %s\n' "$(uname -m)" >&2; return 1 ;;
    esac
    asset="uv-$arch.tar.gz"
    for cmd in curl sha256sum tar python3 install; do
        command -v "$cmd" >/dev/null 2>&1 || {
            printf 'error: uv: %s required\n' "$cmd" >&2
            return 1
        }
    done

    # One release response for tag and asset list: tag and bytes come from the
    # same release, and no redirect string is parsed as a version.
    metadata_script="$(dirname "${BASH_SOURCE[0]}")/uv_release.py"
    release_json="$tmp/release.json"
    curl -fsSL -H 'Accept: application/vnd.github+json' \
        https://api.github.com/repos/astral-sh/uv/releases/latest -o "$release_json" ||
        { printf 'error: uv: cannot download release metadata\n' >&2; return 1; }
    tag="$(python3 "$metadata_script" "$asset" "$release_json")"
    [[ -n $tag ]] || {
        printf 'error: uv: no release asset for %s\n' "$asset" >&2
        return 1
    }

    base="https://github.com/astral-sh/uv/releases/download/$tag"
    curl -fsSL "$base/$asset.sha256" -o "$tmp/$asset.sha256" ||
        { printf 'error: uv: cannot download checksum\n' >&2; return 1; }
    curl -fsSL "$base/$asset" -o "$tmp/$asset" ||
        { printf 'error: uv: cannot download %s\n' "$asset" >&2; return 1; }
    (cd "$tmp" && sha256sum -c "$asset.sha256") ||
        { printf 'error: uv: checksum mismatch for %s\n' "$asset" >&2; return 1; }
    tar -xzf "$tmp/$asset" -C "$tmp" ||
        { printf 'error: uv: %s is not a valid tarball\n' "$asset" >&2; return 1; }
    src="$tmp/uv-$arch"
    [[ -f $src/uv && -f $src/uvx ]] ||
        { printf 'error: uv: %s has no uv binary\n' "$asset" >&2; return 1; }
    ver="$("$src/uv" --version 2>/dev/null | head -n 1 | grep .)" ||
        { printf 'error: uv: uv binary failed to run\n' >&2; return 1; }

    # ~/.local/bin matches the upstream installer's default and the skip guard.
    bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir" 2>/dev/null ||
        { printf 'error: uv: cannot create %s\n' "$bin_dir" >&2; return 1; }
    staged_uv="$bin_dir/.uv.part.$$"
    staged_uvx="$bin_dir/.uvx.part.$$"
    if ! install -m 0755 "$src/uv" "$staged_uv" ||
        ! install -m 0755 "$src/uvx" "$staged_uvx"; then
        rm -f -- "$staged_uv" "$staged_uvx"
        printf 'error: uv: cannot install uv\n' >&2
        return 1
    fi
    if ! mv -f -- "$staged_uv" "$bin_dir/uv" ||
        ! mv -f -- "$staged_uvx" "$bin_dir/uvx"; then
        rm -f -- "$staged_uv" "$staged_uvx"
        printf 'error: uv: cannot install uv\n' >&2
        return 1
    fi
    printf 'installed: uv %s to %s/uv\n' "$ver" "$bin_dir"
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
