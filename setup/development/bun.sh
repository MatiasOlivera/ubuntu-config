#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_bun() {
    local installed_ver
    if installed_ver="$(bun_version 2>/dev/null)"; then
        printf 'skip: bun already installed (%s)\n' "$installed_ver"
        return 0
    fi

    local arch asset
    arch="$(uname -m)"
    case $arch in
        x86_64 | amd64) asset=bun-linux-x64.zip ;;
        aarch64 | arm64 | armv8*) asset=bun-linux-aarch64.zip ;;
        *) printf 'error: bun: unsupported architecture: %s\n' "$arch" >&2; return 1 ;;
    esac

    if ! bun_dependencies; then
        printf 'error: bun: dependency installation failed\n' >&2
        return 1
    fi
    bun_install_verified "$asset"
}

bun_dependencies() {
    sudo apt install -y unzip
}

# Subshell keeps cleanup local and leaves install.sh's EXIT trap untouched.
bun_install_verified() (
    local asset=$1 tag download_url sums_url raw_info tmp artifact sums_file
    local bin_dir staged ver metadata_script
    local api_url=https://api.github.com/repos/oven-sh/bun/releases/latest
    sums_file=SHASUMS256.txt

    local tool
    for tool in curl sha256sum unzip python3 mktemp mkdir cp chmod mv rm head grep; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            printf 'error: bun: %s is required\n' "$tool" >&2
            return 1
        fi
    done

    tmp="$(mktemp -d "${TMPDIR:-/tmp}/bun.XXXXXXXX")" || {
        printf 'error: bun: cannot create temporary directory\n' >&2
        return 1
    }
    staged=""
    trap 'rm -rf -- "$tmp"; [[ -z $staged ]] || rm -f -- "$staged"' EXIT

    if ! curl -fsSL "$api_url" -o "$tmp/release.json"; then
        printf 'error: bun: cannot download release metadata\n' >&2
        return 1
    fi
    metadata_script="$(dirname "${BASH_SOURCE[0]}")/bun_release.py"
    if ! raw_info="$(python3 "$metadata_script" "$asset" "$tmp/release.json")"; then
        return 1
    fi
    IFS=$'\t' read -r tag download_url sums_url <<< "$raw_info"

    if ! curl -fsSL "$sums_url" -o "$tmp/$sums_file"; then
        printf 'error: bun: cannot download checksum\n' >&2
        return 1
    fi
    if ! grep -Fq "  $asset" "$tmp/$sums_file"; then
        printf 'error: bun: checksum file has no entry for %s\n' "$asset" >&2
        return 1
    fi
    artifact="$tmp/$asset"
    if ! curl -fsSL "$download_url" -o "$artifact"; then
        printf 'error: bun: cannot download %s\n' "$asset" >&2
        return 1
    fi
    if ! (cd "$tmp" && grep -F "  $asset" "$sums_file" | sha256sum -c --status -); then
        printf 'error: bun: checksum mismatch for %s (%s)\n' "$asset" "$tag" >&2
        return 1
    fi
    if ! unzip -tqq "$artifact" >/dev/null 2>&1; then
        printf 'error: bun: invalid ZIP archive: %s\n' "$asset" >&2
        return 1
    fi
    if ! unzip -p "$artifact" "${asset%.zip}/bun" > "$tmp/bun" 2>/dev/null; then
        printf 'error: bun: archive has no bun binary\n' >&2
        return 1
    fi
    if [[ ! -s $tmp/bun ]]; then
        printf 'error: bun: archive has no bun binary\n' >&2
        return 1
    fi
    chmod +x "$tmp/bun" || {
        printf 'error: bun: cannot prepare extracted binary\n' >&2
        return 1
    }
    ver="$("$tmp/bun" --version 2>/dev/null | head -n 1 | grep .)" || {
        printf 'error: bun: extracted binary failed to run\n' >&2
        return 1
    }
    if [[ -z $ver ]]; then
        printf 'error: bun: extracted binary returned no version\n' >&2
        return 1
    fi

    bin_dir="$HOME/.bun/bin"
    if ! mkdir -p "$bin_dir" 2>/dev/null; then
        printf 'error: bun: cannot create %s\n' "$bin_dir" >&2
        return 1
    fi
    staged="$(mktemp "$bin_dir/.bun.XXXXXXXX")" || {
        printf 'error: bun: cannot stage verified binary\n' >&2
        return 1
    }
    if ! cp "$tmp/bun" "$staged" || ! chmod 0755 "$staged"; then
        printf 'error: bun: cannot stage verified binary\n' >&2
        return 1
    fi
    if ! "$staged" --version >/dev/null 2>&1; then
        printf 'error: bun: staged binary failed to run\n' >&2
        return 1
    fi
    if ! mv -f -- "$staged" "$bin_dir/bun"; then
        printf 'error: bun: cannot install verified binary\n' >&2
        return 1
    fi
    staged=""
    # dot_zshrc sources ~/.bun/_bun; upstream generates it on install.
    ( IS_BUN_AUTO_UPDATE=true SHELL=zsh BUN_INSTALL="$HOME/.bun" \
        "$bin_dir/bun" completions >/dev/null 2>&1 ) || true
    printf 'installed: bun %s\n' "$ver"
)

# ~/.bun/bin is rc-file-only on PATH; install.sh runs as plain non-login bash.
# The subshell keeps the caller's environment untouched (report stays read-only).
bun_version() {
    ( PATH="$HOME/.bun/bin:$PATH"; bun --version 2>/dev/null | head -n 1 | grep . )
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
