"""Parse and validate GitHub release metadata for AnythingLLM Desktop."""

import argparse
import json
import re
import sys

DIGEST_PATTERN = re.compile(r"sha256:[0-9a-fA-F]{64}")


def parse_release(release, asset):
    """Return the (tag, sha256) pair for one release asset."""
    if not isinstance(release, dict):
        raise ValueError("release must be a JSON object")
    tag = release.get("tag_name")
    if not isinstance(tag, str) or not tag:
        raise ValueError("invalid release tag")
    assets = release.get("assets")
    if not isinstance(assets, list):
        raise ValueError("release assets must be a JSON array")
    for entry in assets:
        if not isinstance(entry, dict) or entry.get("name") != asset:
            continue
        digest = entry.get("digest")
        if not isinstance(digest, str) or not DIGEST_PATTERN.fullmatch(digest):
            raise ValueError("invalid asset SHA-256")
        return tag, digest.split(":", 1)[1]
    raise ValueError("release does not contain the expected asset")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("asset")
    args = parser.parse_args(argv)
    try:
        tag, digest = parse_release(json.load(sys.stdin), args.asset)
    except (json.JSONDecodeError, ValueError) as error:
        print(f"invalid release metadata: {error}", file=sys.stderr)
        return 1
    print(f"{tag}\t{digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
