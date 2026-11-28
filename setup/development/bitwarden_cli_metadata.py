"""Validate Bitwarden CLI release metadata and select the artifact for this host."""

import argparse
import json
import re
import sys

TAG_RE = re.compile(
    r"^cli-v([0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?)$"
)
DIGEST_RE = re.compile(r"^sha256:[0-9a-fA-F]{64}$")
DOWNLOAD_PREFIX = "https://github.com/bitwarden/clients/releases/download/"
ARCHES = ("amd64", "arm64")


def select_asset(releases, arch):
    """Return (version, asset, url, bare sha256) for the newest CLI release."""
    if arch not in ARCHES:
        raise ValueError(f"unsupported architecture: {arch}")
    if not isinstance(releases, list):
        raise ValueError("release metadata must be a JSON array")

    for release in releases:
        if not isinstance(release, dict):
            raise ValueError("release metadata has a non-object release")
        tag_match = TAG_RE.fullmatch(str(release.get("tag_name", "")))
        if not tag_match:
            continue
        tag = tag_match.group(0)
        version = tag_match.group(1)
        asset_name = (
            f"bw-bit-linux-arm64-{version}.zip"
            if arch == "arm64"
            else f"bw-bit-linux-{version}.zip"
        )
        assets = release.get("assets")
        if not isinstance(assets, list):
            raise ValueError(f"release {tag} has no asset list")
        matches = [
            item for item in assets
            if isinstance(item, dict) and item.get("name") == asset_name
        ]
        if len(matches) != 1:
            raise ValueError(f"release {tag} has no unique {asset_name}")
        item = matches[0]

        digest = item.get("digest")
        if not isinstance(digest, str) or not DIGEST_RE.fullmatch(digest):
            raise ValueError(f"no usable sha256 for {asset_name}")
        url = item.get("browser_download_url")
        if url != f"{DOWNLOAD_PREFIX}{tag}/{asset_name}":
            raise ValueError(f"invalid download URL for {asset_name}")
        return version, asset_name, url, digest.split(":", 1)[1]

    raise ValueError("no CLI release found")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", help="JSON array of GitHub releases")
    parser.add_argument("arch", choices=ARCHES, help="host architecture")
    args = parser.parse_args(argv)

    try:
        with open(args.path, encoding="utf-8") as metadata_file:
            releases = json.load(metadata_file)
        result = select_asset(releases, args.arch)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: bitwarden-cli: {error}", file=sys.stderr)
        return 1

    print("\t".join(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
