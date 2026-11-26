import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

# These tests only parse local fixture data; they never access the network.
HELPER = (
    pathlib.Path(__file__).resolve().parents[2]
    / "setup"
    / "development"
    / "bitwarden_cli_metadata.py"
)

TAG = "cli-v2026.11.1"
VERSION = "2026.11.1"
PREFIX = "https://github.com/bitwarden/clients/releases/download/"
DIGEST = "a" * 64
ASSETS = {
    "amd64": "bw-bit-linux-2026.11.1.zip",
    "arm64": "bw-bit-linux-arm64-2026.11.1.zip",
}


def asset(arch, *, name=None, url=None, digest=None):
    filename = name or ASSETS[arch]
    return {
        "name": filename,
        "browser_download_url": (
            url if url is not None else PREFIX + TAG + "/" + filename
        ),
        "digest": digest if digest is not None else "sha256:" + DIGEST,
    }


def releases(assets=None):
    """Newest CLI release, with newer non-CLI releases interleaved as upstream does."""
    chosen = [asset("amd64"), asset("arm64")] if assets is None else assets
    return [
        {"tag_name": "web-v2026.11.2", "assets": []},
        {"tag_name": TAG, "assets": chosen},
        {"tag_name": "cli-v2026.10.9", "assets": []},
    ]


def run_helper(payload, arch="amd64"):
    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / "releases.json"
        path.write_text(payload, encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(HELPER), str(path), arch],
            check=False,
            capture_output=True,
            text=True,
        )


def run_releases(data, arch="amd64"):
    return run_helper(json.dumps(data), arch)


class MetadataTests(unittest.TestCase):
    def test_newest_cli_release_amd64_asset_and_digest(self):
        result = run_releases(releases())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            f"{VERSION}\t{ASSETS['amd64']}\t{PREFIX}{TAG}/{ASSETS['amd64']}\t{DIGEST}",
        )

    def test_arm64_selects_arm64_asset(self):
        result = run_releases(releases(), "arm64")
        self.assertEqual(result.returncode, 0, result.stderr)
        fields = result.stdout.strip().split("\t")
        self.assertEqual(fields[1], ASSETS["arm64"])
        self.assertEqual(fields[2], PREFIX + TAG + "/" + ASSETS["arm64"])
        self.assertEqual(fields[3], DIGEST)

    def test_older_cli_release_is_not_selected_when_newer_is_present(self):
        data = releases()
        data[1]["assets"] = []
        data[2]["tag_name"] = "cli-v2026.10.9"
        data[2]["assets"] = [asset("amd64")]
        result = run_releases(data)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_rejects_missing_digest(self):
        bad = asset("amd64", digest="")
        result = run_releases(releases([bad, asset("arm64")]))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_rejects_non_sha256_digest(self):
        bad = asset("amd64", digest="sha1:" + DIGEST)
        result = run_releases(releases([bad, asset("arm64")]))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_rejects_untrusted_asset_url(self):
        bad = asset("amd64", url=PREFIX + TAG + "/" + ASSETS["amd64"] + "?x=1")
        result = run_releases(releases([bad, asset("arm64")]))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_rejects_missing_asset(self):
        result = run_releases(releases([asset("arm64")]))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_rejects_malformed_or_product_only_releases(self):
        for payload in [
            "{not json",
            json.dumps({"tag_name": TAG}),
            json.dumps([{"tag_name": "web-v2026.11.2", "assets": []}]),
            json.dumps([]),
        ]:
            with self.subTest(payload=payload):
                result = run_helper(payload)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_rejects_unknown_arch(self):
        result = run_releases(releases(), "riscv64")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_failure_is_named_on_stderr(self):
        result = run_helper("{not json")
        self.assertIn("error: bitwarden-cli:", result.stderr)


if __name__ == "__main__":
    unittest.main()
