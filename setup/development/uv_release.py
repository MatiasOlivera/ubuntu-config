#!/usr/bin/env python3
"""Resolve a uv release tag from GitHub's releases/latest metadata."""

import json
import sys


def release_tag(release, asset):
    """Return tag_name only when the expected asset is in this release."""
    tag = release.get("tag_name", "")
    assets = [entry.get("name") for entry in release.get("assets", [])]
    return tag if tag and asset in assets else ""


def main():
    asset, path = sys.argv[1], sys.argv[2]
    with open(path, encoding="utf-8") as handle:
        release = json.load(handle)
    print(release_tag(release, asset))


if __name__ == "__main__":
    main()
