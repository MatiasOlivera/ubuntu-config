import pathlib
import sys
import unittest

# These tests only parse local fixture data; they never access the network.
sys.path.insert(
    0,
    str(pathlib.Path(__file__).resolve().parents[2] / "setup" / "development"),
)

import uv_release


class ReleaseTagTests(unittest.TestCase):
    ASSET = "uv-x86_64-unknown-linux-gnu.tar.gz"

    def test_returns_tag_when_asset_is_published(self):
        release = {"tag_name": "0.13.9", "assets": [{"name": self.ASSET}]}
        self.assertEqual(uv_release.release_tag(release, self.ASSET), "0.13.9")

    def test_empty_when_asset_is_absent(self):
        release = {"tag_name": "0.13.9", "assets": [{"name": "other.tar.gz"}]}
        self.assertEqual(uv_release.release_tag(release, self.ASSET), "")

    def test_empty_when_tag_is_missing(self):
        release = {"assets": [{"name": self.ASSET}]}
        self.assertEqual(uv_release.release_tag(release, self.ASSET), "")

    def test_empty_when_assets_are_missing(self):
        release = {"tag_name": "0.13.9"}
        self.assertEqual(uv_release.release_tag(release, self.ASSET), "")

    def test_ignores_asset_entries_without_a_name(self):
        release = {"tag_name": "0.13.9", "assets": [{}, {"name": self.ASSET}]}
        self.assertEqual(uv_release.release_tag(release, self.ASSET), "0.13.9")


if __name__ == "__main__":
    unittest.main()
