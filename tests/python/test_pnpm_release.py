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
    / "pnpm_release.py"
)

import pnpm_release

ASSET = "pnpm-linux-x64.tar.gz"
URL = f"https://github.com/pnpm/pnpm/releases/download/v12.21.0/{ASSET}"


def make_release(asset=ASSET, digest="a" * 64, url=URL, tag="v12.21.0"):
    item = {"name": asset, "browser_download_url": url}
    if digest is not None:
        item["digest"] = "sha256:" + digest
    return {"tag_name": tag, "assets": [item]}


class ReleaseAssetTests(unittest.TestCase):
    def test_returns_tag_url_and_lowercase_digest(self):
        release = make_release(digest="A" * 64)
        self.assertEqual(
            pnpm_release.release_asset(release, ASSET),
            ("v12.21.0", URL, "a" * 64),
        )

    def test_rejects_absent_or_duplicate_asset(self):
        with self.assertRaisesRegex(ValueError, "no asset named"):
            pnpm_release.release_asset(make_release(asset="other.tar.gz"), ASSET)

        release = make_release()
        release["assets"].append(dict(release["assets"][0]))
        with self.assertRaisesRegex(ValueError, "duplicate assets"):
            pnpm_release.release_asset(release, ASSET)

    def test_rejects_missing_or_malformed_digest(self):
        with self.assertRaisesRegex(ValueError, "no GitHub SHA-256 digest"):
            pnpm_release.release_asset(make_release(digest=None), ASSET)
        with self.assertRaisesRegex(ValueError, "invalid GitHub SHA-256 digest"):
            pnpm_release.release_asset(make_release(digest="not-a-digest"), ASSET)

    def test_rejects_untrusted_url(self):
        bad_urls = [
            URL.replace("github.com", "evil.example"),
            URL.replace("https://", "http://"),
            URL.replace("v12.21.0", "v12.21.1"),
            URL.replace(ASSET, "other.tar.gz"),
        ]
        for url in bad_urls:
            with self.subTest(url=url):
                with self.assertRaisesRegex(ValueError, "invalid download URL"):
                    pnpm_release.release_asset(make_release(url=url), ASSET)

    def test_rejects_invalid_release_shape(self):
        for release in [{}, {"tag_name": "v12.21.0"}, {"assets": []}]:
            with self.subTest(release=release):
                with self.assertRaisesRegex(ValueError, "release metadata|no tag|no asset list"):
                    pnpm_release.release_asset(release, ASSET)


class CommandLineTests(unittest.TestCase):
    def test_prints_validated_tag_url_and_digest(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "release.json"
            path.write_text(json.dumps(make_release()), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(HELPER), ASSET, str(path)],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), f"v12.21.0\t{URL}\t{'a' * 64}")

    def test_fails_closed_on_invalid_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "release.json"
            path.write_text("{not json", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(HELPER), ASSET, str(path)],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("error: pnpm:", result.stderr)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
