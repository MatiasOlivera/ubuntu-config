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
    / "bun_release.py"
)

import bun_release

ASSET = "bun-linux-x64.zip"
PREFIX = "https://github.com/oven-sh/bun/releases/download/bun-v9.9.9/"
URL = PREFIX + ASSET
SUMS_URL = PREFIX + "SHASUMS256.txt"


def make_release(asset=ASSET, url=URL, tag="bun-v9.9.9"):
    names = ["SHASUMS256.txt", "bun-linux-aarch64.zip"]
    release = {
        "assets": [
            {"name": name, "browser_download_url": PREFIX + name}
            for name in names
        ]
    }
    if tag is not None:
        release["tag_name"] = tag
    if asset is not None:
        release["assets"].append({"name": asset, "browser_download_url": url})
    return release


class ReleaseAssetTests(unittest.TestCase):
    def test_returns_tag_and_both_download_urls(self):
        self.assertEqual(
            bun_release.release_asset(make_release(), ASSET),
            ("bun-v9.9.9", URL, SUMS_URL),
        )

    def test_rejects_absent_or_duplicate_asset(self):
        with self.assertRaisesRegex(ValueError, "no asset named"):
            bun_release.release_asset(make_release(asset=None), "missing.zip")

        release = make_release()
        release["assets"].append({"name": ASSET, "browser_download_url": URL})
        with self.assertRaisesRegex(ValueError, "duplicate assets"):
            bun_release.release_asset(release, ASSET)

    def test_rejects_untrusted_asset_url(self):
        bad_url = URL.replace("github.com", "evil.example")
        with self.assertRaisesRegex(ValueError, "invalid download URL"):
            bun_release.release_asset(make_release(url=bad_url), ASSET)

    def test_rejects_invalid_release_shape(self):
        for release in [{}, {"assets": []}, make_release(tag=None)]:
            with self.subTest(release=release):
                with self.assertRaisesRegex(ValueError, "release metadata|no tag"):
                    bun_release.release_asset(release, ASSET)


class CommandLineTests(unittest.TestCase):
    def test_prints_validated_tag_and_urls(self):
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
        self.assertEqual(result.stdout.strip(), f"bun-v9.9.9\t{URL}\t{SUMS_URL}")

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
        self.assertIn("error: bun:", result.stderr)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
