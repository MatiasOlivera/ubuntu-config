#!/usr/bin/env python3
"""Resolve a pnpm release asset, digest and URL from GitHub metadata."""

import json
import re
import sys
from urllib.parse import urlparse

DIGEST_PATTERN = re.compile(r"sha256:[0-9a-fA-F]{64}")


def release_asset(release, asset):
    """Return the (tag, url, sha256) tuple for one exact release asset."""
    if not isinstance(release, dict):
        raise ValueError("release metadata is invalid")
    tag = release.get("tag_name")
    if not isinstance(tag, str) or not tag:
        raise ValueError("release metadata has no tag")

    assets = release.get("assets")
    if not isinstance(assets, list):
        raise ValueError("release metadata has no asset list")
    matches = [
        item for item in assets
        if isinstance(item, dict) and item.get("name") == asset
    ]
    if not matches:
        raise ValueError(f"release has no asset named {asset}")
    if len(matches) != 1:
        raise ValueError(f"release has duplicate assets named {asset}")

    item = matches[0]
    digest = item.get("digest")
    if not isinstance(digest, str) or not digest:
        raise ValueError(f"release has no GitHub SHA-256 digest for {asset}")
    if not DIGEST_PATTERN.fullmatch(digest):
        raise ValueError(f"release has an invalid GitHub SHA-256 digest for {asset}")

    url = item.get("browser_download_url")
    parsed = urlparse(url if isinstance(url, str) else "")
    expected_prefix = f"/pnpm/pnpm/releases/download/{tag}/"
    if (parsed.scheme != "https" or parsed.netloc != "github.com"
            or not parsed.path.startswith(expected_prefix)
            or parsed.path.rsplit("/", 1)[-1] != asset):
        raise ValueError(f"release has an invalid download URL for {asset}")

    return tag, url, digest.split(":", 1)[1].lower()


def main(argv=None):
    asset, path = sys.argv[1], sys.argv[2]
    try:
        with open(path, encoding="utf-8") as handle:
            release = json.load(handle)
        tag, url, digest = release_asset(release, asset)
    except (OSError, ValueError) as error:
        print(f"error: pnpm: {error}", file=sys.stderr)
        return 1

    print(f"{tag}\t{url}\t{digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
