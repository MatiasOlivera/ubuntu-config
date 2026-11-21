#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_pnpm() {
    local installed_ver
    if installed_ver="$(pnpm_version 2>/dev/null)"; then
        printf 'skip: pnpm already installed (%s)\n' "$installed_ver"
        return 0
    fi

    local arch asset
    arch="$(uname -m)"
    case $arch in
        x86_64 | amd64) asset=pnpm-linux-x64.tar.gz ;;
        aarch64 | arm64 | armv8*) asset=pnpm-linux-arm64.tar.gz ;;
        *) printf 'error: pnpm: unsupported architecture: %s\n' "$arch" >&2; return 1 ;;
    esac
    pnpm_install_verified "$asset"
}

# pnpm publishes no checksum file for its standalone release tarballs, so the
# GitHub release-asset digest is the fallback allowed by ADR 0007. One release
# response supplies both the digest and the download URL.
pnpm_release_asset_info() {
    python3 - "$1" "$2" <<'PYEOF'
import json
import re
import sys
from urllib.parse import urlparse


def fail(message):
    print(f"error: pnpm: {message}", file=sys.stderr)
    raise SystemExit(1)


try:
    with open(sys.argv[1], encoding="utf-8") as response:
        release = json.load(response)
except (OSError, json.JSONDecodeError):
    fail("release metadata is invalid")

if not isinstance(release, dict):
    fail("release metadata is invalid")
tag = release.get("tag_name")
if not isinstance(tag, str) or not tag:
    fail("release metadata has no tag")

assets = release.get("assets")
if not isinstance(assets, list):
    fail("release metadata has no asset list")
matches = [item for item in assets if isinstance(item, dict) and item.get("name") == sys.argv[2]]
if not matches:
    fail(f"release has no asset named {sys.argv[2]}")
if len(matches) != 1:
    fail(f"release has duplicate assets named {sys.argv[2]}")

asset = matches[0]
digest = asset.get("digest")
if not isinstance(digest, str) or not digest:
    fail(f"release has no GitHub SHA-256 digest for {sys.argv[2]}")
if not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
    fail(f"release has an invalid GitHub SHA-256 digest for {sys.argv[2]}")

url = asset.get("browser_download_url")
parsed = urlparse(url if isinstance(url, str) else "")
expected_prefix = f"/pnpm/pnpm/releases/download/{tag}/"
if (parsed.scheme != "https" or parsed.netloc != "github.com" or
        not parsed.path.startswith(expected_prefix) or
        parsed.path.rsplit("/", 1)[-1] != sys.argv[2]):
    fail(f"release has an invalid download URL for {sys.argv[2]}")

print(f"{tag}\t{url}\t{digest.split(':', 1)[1].lower()}")
PYEOF
}

# Subshell keeps cleanup local and leaves install.sh's EXIT trap untouched.
pnpm_install_verified() (
    local asset=$1 tag download_url expected_digest raw_info tmp artifact ver
    local bin_dir staged
    local api_url=https://api.github.com/repos/pnpm/pnpm/releases/latest

    local tool
    for tool in curl sha256sum tar python3 mktemp mkdir cp chmod mv rm head grep; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            printf 'error: pnpm: %s is required\n' "$tool" >&2
            return 1
        fi
    done

    tmp="$(mktemp -d "${TMPDIR:-/tmp}/pnpm.XXXXXXXX")" || {
        printf 'error: pnpm: cannot create temporary directory\n' >&2
        return 1
    }
    staged=""
    trap 'rm -rf -- "$tmp"; [[ -z $staged ]] || rm -f -- "$staged"' EXIT

    if ! curl -fsSL "$api_url" -o "$tmp/release.json"; then
        printf 'error: pnpm: cannot download release metadata\n' >&2
        return 1
    fi
    if ! raw_info="$(pnpm_release_asset_info "$tmp/release.json" "$asset")"; then
        return 1
    fi
    IFS=$'\t' read -r tag download_url expected_digest <<< "$raw_info"

    artifact="$tmp/$asset"
    if ! curl -fsSL "$download_url" -o "$artifact"; then
        printf 'error: pnpm: cannot download %s\n' "$asset" >&2
        return 1
    fi
    if ! printf '%s  %s\n' "$expected_digest" "$artifact" |
        sha256sum --check --status -; then
        printf 'error: pnpm: checksum mismatch for %s (%s)\n' "$asset" "$tag" >&2
        return 1
    fi
    if ! tar -tzf "$artifact" >/dev/null 2>&1; then
        printf 'error: pnpm: not a valid tarball\n' >&2
        return 1
    fi
    if ! tar -xzf "$artifact" -C "$tmp" pnpm >/dev/null 2>&1; then
        printf 'error: pnpm: archive has no pnpm binary\n' >&2
        return 1
    fi
    if [[ ! -s $tmp/pnpm ]]; then
        printf 'error: pnpm: archive has no pnpm binary\n' >&2
        return 1
    fi
    chmod +x "$tmp/pnpm" || {
        printf 'error: pnpm: cannot prepare extracted binary\n' >&2
        return 1
    }
    ver="$("$tmp/pnpm" --version 2>/dev/null | head -n 1 | grep .)" || {
        printf 'error: pnpm: extracted binary failed to run\n' >&2
        return 1
    }
    if [[ -z $ver ]]; then
        printf 'error: pnpm: extracted binary returned no version\n' >&2
        return 1
    fi

    bin_dir="$HOME/.local/bin"
    if ! mkdir -p "$bin_dir" 2>/dev/null; then
        printf 'error: pnpm: cannot create %s\n' "$bin_dir" >&2
        return 1
    fi
    staged="$(mktemp "$bin_dir/.pnpm.XXXXXXXX")" || {
        printf 'error: pnpm: cannot stage verified binary\n' >&2
        return 1
    }
    if ! cp "$tmp/pnpm" "$staged" || ! chmod 0755 "$staged"; then
        printf 'error: pnpm: cannot stage verified binary\n' >&2
        return 1
    fi
    if ! "$staged" --version >/dev/null 2>&1; then
        printf 'error: pnpm: staged binary failed to run\n' >&2
        return 1
    fi
    if ! mv -f -- "$staged" "$bin_dir/pnpm"; then
        printf 'error: pnpm: cannot install verified binary\n' >&2
        return 1
    fi
    staged=""
    printf 'installed: pnpm %s\n' "$ver"
)

# ~/.local/bin is rc-file-only on PATH and install.sh runs as plain non-login
# bash. The subshell keeps the report read-only.
pnpm_version() {
    ( PATH="$HOME/.local/bin:$PATH"; pnpm --version 2>/dev/null | head -n 1 | grep . )
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
