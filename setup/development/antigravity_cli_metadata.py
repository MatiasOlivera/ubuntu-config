"""Parse and validate publisher and GitHub release metadata for Antigravity CLI."""

import argparse
import json
import re
import sys
from urllib.parse import urlparse


def parse_manifest(manifest):
    if not isinstance(manifest, dict):
        raise ValueError("manifest must be a JSON object")

    version = manifest.get("version")
    url = manifest.get("url")
    digest = manifest.get("sha512", "")
    if not isinstance(version, str) or not re.fullmatch(
        r"[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?", version
    ):
        raise ValueError("invalid manifest version")
    if not isinstance(url, str):
        raise ValueError("invalid manifest URL")
    parsed = urlparse(url)
    if (
        parsed.scheme != "https"
        or parsed.netloc != "storage.googleapis.com"
        or not parsed.path.startswith("/antigravity-public/antigravity-cli/")
    ):
        raise ValueError("invalid manifest URL")
    if not isinstance(digest, str) or (
        digest and not re.fullmatch(r"[0-9a-fA-F]{128}", digest)
    ):
        raise ValueError("invalid manifest SHA-512")
    return version, url, digest


def parse_github_release(release, version, expected_asset):
    if not isinstance(release, dict):
        raise ValueError("release must be a JSON object")
    tag = release.get("tag_name")
    if tag not in (version, "v" + version):
        raise ValueError("release tag does not match manifest version")
    assets = release.get("assets")
    if not isinstance(assets, list):
        raise ValueError("release assets must be a JSON array")
    for asset in assets:
        if not isinstance(asset, dict) or asset.get("name") != expected_asset:
            continue
        digest = asset.get("digest")
        url = asset.get("browser_download_url")
        if not isinstance(digest, str) or not re.fullmatch(
            r"sha256:[0-9a-fA-F]{64}", digest
        ):
            raise ValueError("invalid GitHub asset SHA-256")
        if not isinstance(url, str):
            raise ValueError("invalid GitHub asset URL")
        parsed = urlparse(url)
        expected_path = (
            "/google-antigravity/antigravity-cli/releases/download/"
            f"{tag}/{expected_asset}"
        )
        if (
            parsed.scheme != "https"
            or parsed.netloc != "github.com"
            or parsed.path != expected_path
        ):
            raise ValueError("invalid GitHub asset URL")
        return url, digest.split(":", 1)[1]
    raise ValueError("GitHub release does not contain the expected asset")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    manifest_command = commands.add_parser("manifest")
    manifest_command.add_argument("path")
    github_command = commands.add_parser("github-release")
    github_command.add_argument("path")
    github_command.add_argument("version")
    github_command.add_argument("asset")
    args = parser.parse_args(argv)

    try:
        with open(args.path, encoding="utf-8") as metadata_file:
            metadata = json.load(metadata_file)
        if args.command == "manifest":
            result = parse_manifest(metadata)
        else:
            result = parse_github_release(metadata, args.version, args.asset)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        label = "publisher manifest" if args.command == "manifest" else "GitHub release"
        print(f"invalid {label}: {error}", file=sys.stderr)
        return 1

    print("\t".join(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
