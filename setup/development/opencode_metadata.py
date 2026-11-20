"""Parse and validate the official OpenCode V2 Homebrew formula."""

import argparse
import re
import sys
from urllib.parse import urlparse

VERSION_PATTERN = re.compile(r'^\s*version\s+"([^"]+)"\s*$', re.MULTILINE)
PAIR_PATTERN = re.compile(
    r'^[ \t]*url[ \t]+"([^"]+)"[ \t]*\n'
    r'(?:[ \t]*\n)*[ \t]*sha256[ \t]+"([^"]+)"[ \t]*$',
    re.MULTILINE,
)
DIGEST_PATTERN = re.compile(r"[0-9a-fA-F]{64}")


def parse_formula(formula, asset):
    """Return the (url, sha256) pair for one Linux V2 release artifact."""
    versions = VERSION_PATTERN.findall(formula)
    if len(versions) != 1 or not versions[0].startswith("2."):
        raise ValueError("invalid V2 formula version")

    matches = []
    for url, digest in PAIR_PATTERN.findall(formula):
        parsed = urlparse(url)
        parts = parsed.path.split("/")
        if (
            parsed.scheme == "https"
            and parsed.netloc == "opencode.ai"
            and len(parts) == 5
            and parts[1:3] == ["files", "bin"]
            and parts[3] == versions[0]
            and parts[4] == asset
            and not parsed.query
            and not parsed.fragment
        ):
            matches.append((url, digest))

    if len(matches) != 1:
        raise ValueError("no unique matching V2 artifact in formula")
    url, digest = matches[0]
    if not DIGEST_PATTERN.fullmatch(digest):
        raise ValueError("invalid V2 formula SHA-256")
    return url, digest.lower()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path")
    parser.add_argument("asset")
    args = parser.parse_args(argv)

    try:
        with open(args.path, encoding="utf-8") as formula_file:
            formula = formula_file.read()
        url, digest = parse_formula(formula, args.asset)
    except (OSError, ValueError) as error:
        print(f"invalid V2 formula: {error}", file=sys.stderr)
        return 1

    print(f"{url}\t{digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
