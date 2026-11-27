#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_bitwarden_cli() {
    local installed_ver
    if installed_ver="$(bitwarden_cli_version 2>/dev/null)"; then
        printf 'skip: bitwarden-cli already installed (%s)\n' "$installed_ver"
    else
        bitwarden_cli_dependencies || return 1
        local tmp rc
        tmp="$(mktemp -d "${TMPDIR:-/tmp}/bitwarden-cli.XXXXXXXX")" || {
            printf 'error: bitwarden-cli: cannot create temporary directory\n' >&2
            return 1
        }
        (bitwarden_cli_install_verified "$tmp")
        rc=$?
        rm -rf -- "$tmp"
        ((rc == 0)) || return "$rc"
    fi
    # ~/.local/bin is rc-file-only; symlink so bw works in non-interactive shells.
    sudo ln -sf "$HOME/.local/bin/bw" /usr/local/bin/bw
}

bitwarden_cli_dependencies() {
    sudo apt install -y unzip
}

# Verify the release asset against GitHub's SHA-256 digest before extracting it.
# Bitwarden publishes no separate checksum asset for CLI releases (ADR 0007
# fallback). The subshell keeps install.sh's EXIT trap untouched.
bitwarden_cli_install_verified() {
    local tmp=$1 arch raw_info asset url digest artifact
    local bin_dir staged ver metadata_script
    case "$(uname -m)" in
        x86_64 | amd64) arch=amd64 ;;
        aarch64 | arm64) arch=arm64 ;;
        *)
            printf 'error: bitwarden-cli: unsupported architecture: %s\n' "$(uname -m)" >&2
            return 1
            ;;
    esac
    for tool in curl python3 sha256sum unzip uname mktemp mkdir cp chmod mv rm head grep; do
        command -v "$tool" >/dev/null 2>&1 || {
            printf 'error: bitwarden-cli: %s required\n' "$tool" >&2
            return 1
        }
    done

    curl -fsSL -H 'Accept: application/vnd.github+json' \
        'https://api.github.com/repos/bitwarden/clients/releases?per_page=100' \
        -o "$tmp/releases.json" || {
        printf 'error: bitwarden-cli: cannot download release metadata\n' >&2
        return 1
    }
    metadata_script="$(dirname "${BASH_SOURCE[0]}")/bitwarden_cli_metadata.py"
    raw_info="$(python3 "$metadata_script" "$tmp/releases.json" "$arch")" || return 1
    IFS=$'\t' read -r _ asset url digest <<< "$raw_info"

    artifact="$tmp/$asset"
    curl -fsSL "$url" -o "$artifact" || {
        printf 'error: bitwarden-cli: cannot download %s\n' "$asset" >&2
        return 1
    }
    printf '%s  %s\n' "$digest" "$artifact" > "$tmp/checksum"
    sha256sum --check --status "$tmp/checksum" || {
        printf 'error: bitwarden-cli: checksum mismatch for %s\n' "$asset" >&2
        return 1
    }

    unzip -tqq "$artifact" >/dev/null 2>&1 || {
        printf 'error: bitwarden-cli: invalid ZIP archive: %s\n' "$asset" >&2
        return 1
    }
    if ! unzip -p "$artifact" bw > "$tmp/bw" 2>/dev/null || [[ ! -s $tmp/bw ]]; then
        printf 'error: bitwarden-cli: archive has no bw binary\n' >&2
        return 1
    fi
    chmod +x "$tmp/bw" || {
        printf 'error: bitwarden-cli: cannot prepare extracted binary\n' >&2
        return 1
    }
    ver="$("$tmp/bw" --version 2>/dev/null | head -n 1 | grep .)" || {
        printf 'error: bitwarden-cli: extracted binary failed to run\n' >&2
        return 1
    }
    [[ -n $ver ]] || {
        printf 'error: bitwarden-cli: extracted binary returned no version\n' >&2
        return 1
    }

    bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir" || {
        printf 'error: bitwarden-cli: cannot create %s\n' "$bin_dir" >&2
        return 1
    }
    staged="$bin_dir/.bw.part.$$"
    if ! cp "$tmp/bw" "$staged" || ! chmod 0755 "$staged"; then
        rm -f -- "$staged"
        printf 'error: bitwarden-cli: cannot stage verified binary\n' >&2
        return 1
    fi
    if ! "$staged" --version >/dev/null 2>&1; then
        rm -f -- "$staged"
        printf 'error: bitwarden-cli: staged binary failed to run\n' >&2
        return 1
    fi
    if ! mv -f -- "$staged" "$bin_dir/bw"; then
        rm -f -- "$staged"
        printf 'error: bitwarden-cli: cannot install verified binary\n' >&2
        return 1
    fi
    printf 'installed: bitwarden-cli %s to %s/bw\n' "$ver" "$bin_dir"
}

# Check the installed path, not a generic bw on PATH: a pre-existing snap
# install must not suppress migration. The subshell keeps report calls read-only.
bitwarden_cli_version() {
    ( "$HOME/.local/bin/bw" --version 2>/dev/null | head -n 1 | grep . )
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
