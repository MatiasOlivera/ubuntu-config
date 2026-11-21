#!/usr/bin/env python3
"""Resolve a bun release tag and asset URLs from GitHub metadata."""

import json
import sys

SUMS = "SHASUMS256.txt"
URL_PREFIX = "https://github.com/oven-sh/bun/releases/download/"


def release_asset(release, asset):
    """Return the (tag, asset URL, checksum URL) tuple for one bun release."""
    if not isinstance(release, dict):
        raise ValueError("release metadata is invalid")
    tag = release.get("tag_name")
    if not isinstance(tag, str) or not tag:
        raise ValueError("release metadata has no tag")

    assets = release.get("assets")
    if not isinstance(assets, list):
        raise ValueError("release metadata has no asset list")
    by_name = {}
    for item in assets:
        if isinstance(item, dict) and isinstance(item.get("name"), str):
            by_name.setdefault(item["name"], []).append(item)

    prefix = URL_PREFIX + tag + "/"
    urls = {}
    for name in (SUMS, asset):
        matches = by_name.get(name, [])
        if not matches:
            raise ValueError(f"release has no asset named {name}")
        if len(matches) != 1:
            raise ValueError(f"release has duplicate assets named {name}")
        url = matches[0].get("browser_download_url")
        if url != prefix + name:
            raise ValueError(f"release has an invalid download URL for {name}")
        urls[name] = url

    return tag, urls[asset], urls[SUMS]


def main(argv=None):
    asset, path = sys.argv[1], sys.argv[2]
    try:
        with open(path, encoding="utf-8") as handle:
            release = json.load(handle)
        tag, asset_url, sums_url = release_asset(release, asset)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: bun: {error}", file=sys.stderr)
        return 1

    print(f"{tag}\t{asset_url}\t{sums_url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
