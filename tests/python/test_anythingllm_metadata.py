import json
import pathlib
import subprocess
import sys
import unittest

# These tests only parse local fixture data; they never access the network.
sys.path.insert(
    0,
    str(pathlib.Path(__file__).resolve().parents[2] / "setup" / "desktop-apps"),
)
HELPER = (
    pathlib.Path(__file__).resolve().parents[2]
    / "setup"
    / "desktop-apps"
    / "anythingllm_metadata.py"
)

import anythingllm_metadata

ASSET = "AnythingLLMDesktop.AppImage"
ARM_ASSET = "AnythingLLMDesktop-Arm64.AppImage"
DIGEST = "a" * 64
TAG = "v1.19.0"


def make_release(assets=None, tag=TAG):
    if assets is None:
        assets = [
            {"name": ARM_ASSET, "digest": "sha256:" + "b" * 64},
            {
                "name": ASSET,
                "digest": "sha256:" + DIGEST,
                "size": 20,
                "state": "uploaded",
            },
        ]
    return {"tag_name": tag, "assets": assets}


class ParseReleaseTests(unittest.TestCase):
    def test_parses_digest_for_exact_asset(self):
        self.assertEqual(
            anythingllm_metadata.parse_release(make_release(), ASSET),
            (TAG, DIGEST),
        )

    def test_rejects_missing_asset(self):
        release = make_release(assets=[])
        with self.assertRaisesRegex(ValueError, "expected asset"):
            anythingllm_metadata.parse_release(release, ASSET)

    def test_rejects_missing_digest(self):
        release = make_release(assets=[{"name": ASSET, "size": 20}])
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            anythingllm_metadata.parse_release(release, ASSET)

    def test_rejects_non_sha256_or_malformed_digest(self):
        for digest in ("md5:" + "a" * 32, "sha256:short", "sha256:" + "z" * 64):
            with self.subTest(digest=digest):
                release = make_release(assets=[{"name": ASSET, "digest": digest}])
                with self.assertRaisesRegex(ValueError, "SHA-256"):
                    anythingllm_metadata.parse_release(release, ASSET)

    def test_rejects_digest_of_wrong_type(self):
        release = make_release(assets=[{"name": ASSET, "digest": 12345}])
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            anythingllm_metadata.parse_release(release, ASSET)

    def test_rejects_malformed_release_shapes(self):
        bad_releases = [
            [],
            {"assets": [{"name": ASSET, "digest": "sha256:" + DIGEST}]},
            {"tag_name": TAG, "assets": {}},
            {"tag_name": TAG, "assets": ["not-an-object"]},
        ]
        for release in bad_releases:
            with self.subTest(release=release):
                with self.assertRaises(ValueError):
                    anythingllm_metadata.parse_release(release, ASSET)


class CommandLineTests(unittest.TestCase):
    def run_helper(self, payload):
        return subprocess.run(
            [sys.executable, str(HELPER), ASSET],
            input=payload,
            check=False,
            capture_output=True,
            text=True,
        )

    def test_prints_validated_tag_and_digest(self):
        result = self.run_helper(json.dumps(make_release()))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), f"{TAG}\t{DIGEST}")

    def test_fails_closed_on_malformed_json(self):
        result = self.run_helper("{not json")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid release metadata", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_fails_closed_on_missing_asset(self):
        result = self.run_helper(json.dumps(make_release(assets=[])))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid release metadata", result.stderr)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
