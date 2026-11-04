#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_copilot() {
    local installed_ver
    if installed_ver="$(copilot_version 2>/dev/null)"; then
        printf 'skip: copilot already installed (%s)\n' "$installed_ver"
        return 0
    fi
    local tmp rc
    tmp="$(mktemp -d)" || return 1
    # Subshell keeps this trap-free: install.sh owns the EXIT trap (sudo keepalive).
    (copilot_install_verified "$tmp")
    rc=$?
    rm -rf -- "$tmp"
    return "$rc"
}

# Installs the latest release tarball only after verifying it against the
# SHA256SUMS.txt GitHub publishes in the same release. The gh.io installer
# script is deliberately not executed: no checksum or signature is published
# for it, so piping it into bash would run unverifiable remote code.
copilot_install_verified() {
    local tmp=$1 platform arch tag base asset install_dir
    case "$(uname -s)" in
        Linux*) platform=linux ;;
        Darwin*) platform=darwin ;;
        *) printf 'error: copilot: unsupported OS: %s\n' "$(uname -s)" >&2; exit 1 ;;
    esac
    case "$(uname -m)" in
        x86_64 | amd64) arch=x64 ;;
        aarch64 | arm64) arch=arm64 ;;
        *) printf 'error: copilot: unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
    esac
    command -v curl >/dev/null 2>&1 || { printf 'error: copilot: curl required\n' >&2; exit 1; }
    command -v sha256sum >/dev/null 2>&1 || { printf 'error: copilot: sha256sum required\n' >&2; exit 1; }

    # One tag for both downloads: resolving "latest" twice could straddle a
    # release published mid-run and fail the checksum with a misleading error.
    tag="$(curl -fsSI https://github.com/github/copilot-cli/releases/latest |
        sed -n 's/^[Ll]ocation: .*\/tag\///p' | tr -d '[:space:]')"
    [[ -n $tag ]] ||
        { printf 'error: copilot: cannot determine latest release\n' >&2; exit 1; }
    base="https://github.com/github/copilot-cli/releases/download/$tag"
    asset="copilot-${platform}-${arch}.tar.gz"
    curl -fsSL "$base/SHA256SUMS.txt" -o "$tmp/SHA256SUMS.txt" ||
        { printf 'error: copilot: cannot download checksums\n' >&2; exit 1; }
    curl -fsSL "$base/$asset" -o "$tmp/$asset" ||
        { printf 'error: copilot: cannot download %s\n' "$asset" >&2; exit 1; }
    grep -F " $asset" "$tmp/SHA256SUMS.txt" >"$tmp/checksum-line" || {
        printf 'error: copilot: no checksum published for %s\n' "$asset" >&2
        exit 1
    }
    (cd "$tmp" && sha256sum -c checksum-line) ||
        { printf 'error: copilot: checksum mismatch for %s\n' "$asset" >&2; exit 1; }
    tar -xzf "$tmp/$asset" -C "$tmp" ||
        { printf 'error: copilot: %s is not a valid tarball\n' "$asset" >&2; exit 1; }
    [[ -f $tmp/copilot ]] ||
        { printf 'error: copilot: %s has no copilot binary\n' "$asset" >&2; exit 1; }

    # PREFIX mirrors the upstream installer's documented knob; default is
    # /usr/local (always on PATH; sudo is already kept alive by install.sh).
    install_dir="${PREFIX:-/usr/local}/bin"
    mkdir -p "$install_dir" 2>/dev/null || sudo mkdir -p "$install_dir" ||
        { printf 'error: copilot: cannot create %s\n' "$install_dir" >&2; exit 1; }
    if [[ -w $install_dir ]]; then
        install -m 0755 "$tmp/copilot" "$install_dir/copilot" || exit 1
    else
        sudo install -m 0755 "$tmp/copilot" "$install_dir/copilot" || exit 1
    fi
    printf 'installed: copilot %s to %s\n' \
        "$("$install_dir/copilot" --version 2>/dev/null | head -n 1 | grep .)" \
        "$install_dir/copilot"
}

copilot_version() {
    copilot --version 2>/dev/null | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
