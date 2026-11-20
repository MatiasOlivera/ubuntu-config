#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../../helpers/dispatcher.sh"

fnm_dependencies() {
    sudo apt install -y unzip
}

install_fnm() {
    local installed_ver
    if installed_ver="$(fnm_version 2>/dev/null)"; then
        printf 'skip: fnm already installed (%s)\n' "$installed_ver"
        return 0
    fi

    local arch asset
    arch="$(uname -m)"
    case $arch in
        x86_64 | amd64) asset=fnm-linux.zip ;;
        aarch* | arm64 | armv8*) asset=fnm-arm64.zip ;;
        arm | armv7*) asset=fnm-arm32.zip ;;
        *) printf 'error: fnm: unsupported architecture: %s\n' "$arch" >&2; return 1 ;;
    esac

    if ! fnm_dependencies; then
        printf 'error: fnm: dependency installation failed\n' >&2
        return 1
    fi
    fnm_install_verified "$asset"
}

# Reads one release response and returns its tag, exact asset URL, and digest.
# The digest is GitHub's release-asset digest fallback: current fnm releases do
# not publish a separate checksum or signature covering the binary asset.
fnm_release_asset_info() {
    python3 - "$1" "$2" <<'PYEOF'
import json
import re
import sys
from urllib.parse import urlparse


def fail(message):
    print(f"error: fnm: {message}", file=sys.stderr)
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
expected_prefix = f"/Schniz/fnm/releases/download/{tag}/"
if (parsed.scheme != "https" or parsed.netloc != "github.com" or
        not parsed.path.startswith(expected_prefix) or
        parsed.path.rsplit("/", 1)[-1] != sys.argv[2]):
    fail(f"release has an invalid download URL for {sys.argv[2]}")

print(f"{tag}\t{url}\t{digest.split(':', 1)[1].lower()}")
PYEOF
}

# Subshell keeps cleanup local and leaves setup/post-install.sh's traps alone.
fnm_install_verified() (
    local asset=$1 tag download_url expected_digest raw_info tmp artifact entry
    local install_dir staged installed_ver
    local api_url=https://api.github.com/repos/Schniz/fnm/releases/latest

    local tool
    for tool in curl sha256sum python3 unzip mktemp mkdir chmod cp mv rm; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            printf 'error: fnm: %s is required\n' "$tool" >&2
            return 1
        fi
    done

    tmp="$(mktemp -d "${TMPDIR:-/tmp}/fnm.XXXXXXXX")" || {
        printf 'error: fnm: cannot create temporary directory\n' >&2
        return 1
    }
    staged=""
    trap 'rm -rf -- "$tmp"; [[ -z $staged ]] || rm -f -- "$staged"' EXIT

    if ! curl -fsSL "$api_url" -o "$tmp/release.json"; then
        printf 'error: fnm: cannot fetch release metadata\n' >&2
        return 1
    fi
    if ! raw_info="$(fnm_release_asset_info "$tmp/release.json" "$asset")"; then
        return 1
    fi
    IFS=$'\t' read -r tag download_url expected_digest <<< "$raw_info"

    artifact="$tmp/$asset"
    if ! curl -fsSL "$download_url" -o "$artifact"; then
        printf 'error: fnm: cannot download %s\n' "$asset" >&2
        return 1
    fi
    if ! printf '%s  %s\n' "$expected_digest" "$artifact" |
        sha256sum --check --status -; then
        printf 'error: fnm: checksum mismatch for %s (%s)\n' "$asset" "$tag" >&2
        return 1
    fi
    if ! unzip -tqq "$artifact" >/dev/null 2>&1; then
        printf 'error: fnm: invalid ZIP archive: %s\n' "$asset" >&2
        return 1
    fi

    entry="${asset%.zip}/fnm"
    if ! unzip -p "$artifact" "$entry" > "$tmp/fnm"; then
        if ! unzip -p "$artifact" fnm > "$tmp/fnm"; then
            printf 'error: fnm: archive has no fnm executable\n' >&2
            return 1
        fi
    fi
    if [[ ! -s $tmp/fnm ]]; then
        printf 'error: fnm: archive has no fnm executable\n' >&2
        return 1
    fi
    chmod +x "$tmp/fnm" || {
        printf 'error: fnm: cannot prepare extracted binary\n' >&2
        return 1
    }
    if ! installed_ver="$("$tmp/fnm" --version 2>/dev/null)"; then
        printf 'error: fnm: extracted binary failed to run\n' >&2
        return 1
    fi
    installed_ver="${installed_ver%%$'\n'*}"
    if [[ -z $installed_ver ]]; then
        printf 'error: fnm: extracted binary returned no version\n' >&2
        return 1
    fi

    install_dir="$HOME/.local/share/fnm"
    if ! mkdir -p "$install_dir"; then
        printf 'error: fnm: cannot create install directory\n' >&2
        return 1
    fi
    staged="$(mktemp "$install_dir/.fnm.XXXXXXXX")" || {
        printf 'error: fnm: cannot stage verified binary\n' >&2
        return 1
    }
    if ! cp "$tmp/fnm" "$staged" || ! chmod +x "$staged"; then
        printf 'error: fnm: cannot stage verified binary\n' >&2
        return 1
    fi
    if ! "$staged" --version >/dev/null 2>&1; then
        printf 'error: fnm: staged binary failed to run\n' >&2
        return 1
    fi
    if ! mv -f -- "$staged" "$install_dir/fnm"; then
        printf 'error: fnm: cannot install verified binary\n' >&2
        return 1
    fi
    staged=""
    printf 'installed: fnm %s (verified with GitHub SHA-256)\n' "$installed_ver"
)

fnm_version() {
    export PATH="$HOME/.local/share/fnm:$PATH"
    fnm --version 2>/dev/null | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
