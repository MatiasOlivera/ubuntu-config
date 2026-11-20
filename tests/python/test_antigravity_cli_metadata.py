import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

# These tests only parse local fixture data; they never access the network.
sys.path.insert(
    0,
    str(pathlib.Path(__file__).resolve().parents[2] / "setup" / "development"),
)
HELPER = (
    pathlib.Path(__file__).resolve().parents[2]
    / "setup"
    / "development"
    / "antigravity_cli_metadata.py"
)

import antigravity_cli_metadata


class ManifestTests(unittest.TestCase):
    def test_parses_valid_publisher_manifest(self):
        manifest = {
            "version": "1.5.13",
            "url": (
                "https://storage.googleapis.com/antigravity-public/"
                "antigravity-cli/1.5.13/linux-x64/cli_linux_x64.tar.gz"
            ),
            "sha512": "a" * 128,
        }

        self.assertEqual(
            antigravity_cli_metadata.parse_manifest(manifest),
            (
                "1.5.13",
                "https://storage.googleapis.com/antigravity-public/"
                "antigravity-cli/1.5.13/linux-x64/cli_linux_x64.tar.gz",
                "a" * 128,
            ),
        )

    def test_missing_publisher_digest_returns_empty_value_for_fallback(self):
        manifest = {
            "version": "1.5.13",
            "url": (
                "https://storage.googleapis.com/antigravity-public/"
                "antigravity-cli/1.5.13/linux-x64/cli_linux_x64.tar.gz"
            ),
        }

        self.assertEqual(
            antigravity_cli_metadata.parse_manifest(manifest),
            (
                "1.5.13",
                "https://storage.googleapis.com/antigravity-public/"
                "antigravity-cli/1.5.13/linux-x64/cli_linux_x64.tar.gz",
                "",
            ),
        )


class GitHubReleaseTests(unittest.TestCase):
    def test_parses_digest_for_exact_release_asset(self):
        digest = "b" * 64
        release = {
            "tag_name": "1.5.13",
            "assets": [
                {
                    "name": "agy_cli_linux_x64.tar.gz",
                    "digest": f"sha256:{digest}",
                    "browser_download_url": (
                        "https://github.com/google-antigravity/antigravity-cli/"
                        "releases/download/1.5.13/agy_cli_linux_x64.tar.gz"
                    ),
                }
            ],
        }

        self.assertEqual(
            antigravity_cli_metadata.parse_github_release(
                release, "1.5.13", "agy_cli_linux_x64.tar.gz"
            ),
            (
                "https://github.com/google-antigravity/antigravity-cli/"
                "releases/download/1.5.13/agy_cli_linux_x64.tar.gz",
                digest,
            ),
        )

    def test_missing_github_digest_is_rejected(self):
        release = {
            "tag_name": "1.5.13",
            "assets": [
                {
                    "name": "agy_cli_linux_x64.tar.gz",
                    "browser_download_url": (
                        "https://github.com/google-antigravity/antigravity-cli/"
                        "releases/download/1.5.13/agy_cli_linux_x64.tar.gz"
                    ),
                }
            ],
        }

        with self.assertRaisesRegex(ValueError, "SHA-256"):
            antigravity_cli_metadata.parse_github_release(
                release, "1.5.13", "agy_cli_linux_x64.tar.gz"
            )


class CommandLineTests(unittest.TestCase):
    def test_manifest_command_prints_validated_metadata(self):
        # This URL is metadata input only; the helper never makes network calls.
        manifest = {
            "version": "1.5.13",
            "url": (
                "https://storage.googleapis.com/antigravity-public/"
                "antigravity-cli/1.5.13/linux-x64/cli_linux_x64.tar.gz"
            ),
            "sha512": "a" * 128,
        }
        with tempfile.TemporaryDirectory() as directory:
            manifest_path = pathlib.Path(directory) / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(HELPER), "manifest", str(manifest_path)],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            f"1.5.13\t{manifest['url']}\t{'a' * 128}",
        )

    def test_github_release_command_prints_exact_asset_metadata(self):
        digest = "b" * 64
        url = (
            "https://github.com/google-antigravity/antigravity-cli/"
            "releases/download/1.5.13/agy_cli_linux_x64.tar.gz"
        )
        release = {
            "tag_name": "1.5.13",
            "assets": [
                {
                    "name": "agy_cli_linux_x64.tar.gz",
                    "digest": f"sha256:{digest}",
                    "browser_download_url": url,
                }
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            release_path = pathlib.Path(directory) / "release.json"
            release_path.write_text(json.dumps(release), encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    str(HELPER),
                    "github-release",
                    str(release_path),
                    "1.5.13",
                    "agy_cli_linux_x64.tar.gz",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), f"{url}\t{digest}")


if __name__ == "__main__":
    unittest.main()
