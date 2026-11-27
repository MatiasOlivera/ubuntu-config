"""Validate chezmoi release metadata and select the artifact for this host."""

import json
import re
import sys
from pathlib import Path

TAG_RE = re.compile(r"^v([0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?)$")
DIGEST_RE = re.compile(r"^[0-9a-fA-F]{64}$")
DOWNLOAD_PREFIX = "https://github.com/twpayne/chezmoi/releases/download/"
ARCHES = ("amd64", "arm64")


def fail(message):
    print(f"error: chezmoi: {message}", file=sys.stderr)
    return 1


def select_release(release, arch):
    """Return (version, asset, artifact URL, checksums URL) for the release."""
    if arch not in ARCHES:
        raise ValueError(f"unsupported architecture: {arch}")
    if not isinstance(release, dict):
        raise ValueError("release metadata must be an object")

    tag_match = TAG_RE.fullmatch(str(release.get("tag_name", "")))
    if not tag_match:
        raise ValueError("no usable chezmoi release tag")
    tag = tag_match.group(0)
    version = tag_match.group(1)

    assets = release.get("assets")
    if not isinstance(assets, list):
        raise ValueError("release has no asset list")

    artifact = f"chezmoi_{version}_linux_{arch}.tar.gz"
    checksums = f"chezmoi_{version}_checksums.txt"

    def asset_url(name):
        matches = [
            item for item in assets
            if isinstance(item, dict) and item.get("name") == name
        ]
        if len(matches) != 1:
            raise ValueError(f"release has no unique {name}")
        expected = f"{DOWNLOAD_PREFIX}{tag}/{name}"
        if matches[0].get("browser_download_url") != expected:
            raise ValueError(f"invalid download URL for {name}")
        return expected

    return version, artifact, asset_url(artifact), asset_url(checksums)


def select_checksum(path, asset):
    """Return the one usable maintainer digest for the exact artifact name."""
    digests = []
    with open(path, encoding="utf-8") as checksums_file:
        for line in checksums_file:
            fields = line.rstrip("\n").split("  ", 1)
            if len(fields) != 2 or fields[1] != asset:
                continue
            if not DIGEST_RE.fullmatch(fields[0]):
                raise ValueError(f"no usable sha256 for {asset}")
            digests.append(fields[0].lower())
    if len(digests) != 1:
        raise ValueError(f"no unique sha256 for {asset}")
    return digests[0]


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 3 or args[0] not in ("release", "checksum"):
        return fail("usage: chezmoi_metadata.py release|checksum <path> <arch|asset>")

    try:
        if args[0] == "release":
            with open(args[1], encoding="utf-8") as metadata_file:
                release = json.load(metadata_file)
            result = select_release(release, args[2])
        else:
            result = (select_checksum(args[1], args[2]),)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        return fail(str(error))

    print("\t".join(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
