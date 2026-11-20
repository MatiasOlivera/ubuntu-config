#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_opencode() {
    local installed_ver
    if installed_ver="$(opencode_version 2>/dev/null)"; then
        printf 'skip: opencode already installed (%s)\n' "$installed_ver"
        return 0
    fi

    local tmp rc
    tmp="$(mktemp -d)" || {
        printf 'error: opencode: cannot create temporary directory\n' >&2
        return 1
    }
    (opencode_install_verified "$tmp")
    rc=$?
    rm -rf -- "$tmp"
    return "$rc"
}

opencode_install_verified() {
    local tmp=$1 arch asset formula_url metadata artifact_url digest
    local install_dir staged installed_ver metadata_script
    formula_url="https://raw.githubusercontent.com/anomalyco/homebrew-tap/master/opencode-v2.rb"

    case "$(uname -s)" in
        Linux*) ;;
        *)
            printf 'error: opencode: unsupported OS: %s\n' "$(uname -s)" >&2
            return 1
            ;;
    esac
    case "$(uname -m)" in
        x86_64 | amd64) arch=x64-baseline ;;
        aarch64 | arm64) arch=arm64 ;;
        *)
            printf 'error: opencode: unsupported architecture: %s\n' "$(uname -m)" >&2
            return 1
            ;;
    esac

    command -v curl >/dev/null 2>&1 || {
        printf 'error: opencode: curl required\n' >&2
        return 1
    }
    command -v python3 >/dev/null 2>&1 || {
        printf 'error: opencode: python3 required\n' >&2
        return 1
    }
    command -v sha256sum >/dev/null 2>&1 || {
        printf 'error: opencode: sha256sum required\n' >&2
        return 1
    }
    command -v tar >/dev/null 2>&1 || {
        printf 'error: opencode: tar required\n' >&2
        return 1
    }

    curl -fsSL "$formula_url" -o "$tmp/opencode-v2.rb" || {
        printf 'error: opencode: cannot download V2 formula\n' >&2
        return 1
    }

    metadata_script="$(dirname "${BASH_SOURCE[0]}")/opencode_metadata.py"
    if ! metadata="$(python3 "$metadata_script" "$tmp/opencode-v2.rb" "opencode-linux-$arch.tar.gz")"; then
        printf 'error: opencode: malformed V2 formula or missing checksum for %s\n' \
            "opencode-linux-$arch.tar.gz" >&2
        return 1
    fi
    IFS=$'\t' read -r artifact_url digest <<< "$metadata"
    asset="${artifact_url##*/}"

    curl -fsSL "$artifact_url" -o "$tmp/$asset" || {
        printf 'error: opencode: cannot download %s\n' "$asset" >&2
        return 1
    }
    printf '%s  %s\n' "$digest" "$tmp/$asset" > "$tmp/checksum"
    sha256sum --check --status "$tmp/checksum" || {
        printf 'error: opencode: checksum mismatch for %s\n' "$asset" >&2
        return 1
    }

    tar -xzf "$tmp/$asset" -C "$tmp" opencode 2>/dev/null || {
        printf 'error: opencode: cannot extract opencode from %s\n' "$asset" >&2
        return 1
    }
    [[ -f $tmp/opencode ]] || {
        printf 'error: opencode: %s has no opencode binary\n' "$asset" >&2
        return 1
    }

    install_dir="$HOME/.opencode/bin"
    mkdir -p "$install_dir" || {
        printf 'error: opencode: cannot create %s\n' "$install_dir" >&2
        return 1
    }
    staged="$install_dir/.opencode.part.$$"
    install -m 0755 "$tmp/opencode" "$staged" || {
        printf 'error: opencode: cannot stage binary in %s\n' "$install_dir" >&2
        return 1
    }
    if ! "$staged" --version > "$tmp/version" 2>&1; then
        rm -f -- "$staged"
        printf 'error: opencode: staged binary failed to run\n' >&2
        return 1
    fi
    installed_ver="$(head -n 1 "$tmp/version" | grep .)" || {
        rm -f -- "$staged"
        printf 'error: opencode: staged binary returned no version\n' >&2
        return 1
    }
    mv -f -- "$staged" "$install_dir/opencode" || {
        rm -f -- "$staged"
        printf 'error: opencode: cannot install binary in %s\n' "$install_dir" >&2
        return 1
    }
    printf 'installed: opencode %s to %s/opencode\n' "$installed_ver" "$install_dir"
}

opencode_version() {
    opencode --version 2>/dev/null | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
