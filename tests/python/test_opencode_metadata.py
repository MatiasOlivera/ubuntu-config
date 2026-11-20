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
    / "opencode_metadata.py"
)

import opencode_metadata


X64_ASSET = "opencode-linux-x64-baseline.tar.gz"
ARM64_ASSET = "opencode-linux-arm64.tar.gz"


def make_formula(version="2.3.2", pairs=None):
    if pairs is None:
        pairs = [
            (f"https://opencode.ai/files/bin/{version}/{X64_ASSET}", "a" * 64),
            (f"https://opencode.ai/files/bin/{version}/{ARM64_ASSET}", "b" * 64),
        ]
    entries = "\n".join(f'    url "{url}"\n    sha256 "{digest}"' for url, digest in pairs)
    return (
        "class OpencodeV2 < Formula\n"
        f'  version "{version}"\n'
        "  on_linux do\n"
        f"{entries}\n"
        "  end\n"
        "end\n"
    )


class ParseFormulaTests(unittest.TestCase):
    def test_parses_matching_x64_artifact(self):
        self.assertEqual(
            opencode_metadata.parse_formula(make_formula(), X64_ASSET),
            ("https://opencode.ai/files/bin/2.3.2/" + X64_ASSET, "a" * 64),
        )

    def test_parses_matching_arm64_artifact_and_lowercases_digest(self):
        formula = make_formula(
            pairs=[
                (
                    "https://opencode.ai/files/bin/2.3.2/" + ARM64_ASSET,
                    "B" * 64,
                )
            ]
        )
        self.assertEqual(
            opencode_metadata.parse_formula(formula, ARM64_ASSET),
            ("https://opencode.ai/files/bin/2.3.2/" + ARM64_ASSET, "b" * 64),
        )

    def test_rejects_non_v2_version(self):
        with self.assertRaisesRegex(ValueError, "V2"):
            opencode_metadata.parse_formula(make_formula(version="1.19.6"), X64_ASSET)

    def test_rejects_missing_or_duplicate_version(self):
        no_version = 'class OpencodeV2 < Formula\n    url "https://opencode.ai/files/bin/2.3.2/' + X64_ASSET + '"\n'
        with self.assertRaisesRegex(ValueError, "V2"):
            opencode_metadata.parse_formula(no_version, X64_ASSET)

        two_versions = make_formula().replace(
            '  version "2.3.2"', '  version "2.3.2"\n  version "2.3.3"'
        )
        with self.assertRaisesRegex(ValueError, "V2"):
            opencode_metadata.parse_formula(two_versions, X64_ASSET)

    def test_rejects_unapproved_host_path_or_query(self):
        bad_urls = [
            f"https://example.invalid/files/bin/2.3.2/{X64_ASSET}",
            f"https://opencode.ai/other/bin/2.3.2/{X64_ASSET}",
            f"https://opencode.ai/files/bin/2.3.3/{X64_ASSET}",
            f"https://opencode.ai/files/bin/2.3.2/{X64_ASSET}?x=1",
        ]
        for url in bad_urls:
            with self.subTest(url=url):
                formula = make_formula(pairs=[(url, "a" * 64)])
                with self.assertRaisesRegex(ValueError, "unique"):
                    opencode_metadata.parse_formula(formula, X64_ASSET)

    def test_rejects_malformed_or_missing_digest(self):
        base = f"https://opencode.ai/files/bin/2.3.2/{X64_ASSET}"
        bad = make_formula(pairs=[(base, "not-a-digest")])
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            opencode_metadata.parse_formula(bad, X64_ASSET)

        missing = (
            "class OpencodeV2 < Formula\n"
            '  version "2.3.2"\n'
            f'    url "{base}"\n'
            "end\n"
        )
        with self.assertRaisesRegex(ValueError, "unique"):
            opencode_metadata.parse_formula(missing, X64_ASSET)

    def test_rejects_duplicate_matching_entries(self):
        base = f"https://opencode.ai/files/bin/2.3.2/{X64_ASSET}"
        formula = make_formula(pairs=[(base, "a" * 64), (base, "a" * 64)])
        with self.assertRaisesRegex(ValueError, "unique"):
            opencode_metadata.parse_formula(formula, X64_ASSET)

    def test_rejects_asset_with_no_formula_entry(self):
        with self.assertRaisesRegex(ValueError, "unique"):
            opencode_metadata.parse_formula(make_formula(), "opencode-linux-riscv64.tar.gz")


class CommandLineTests(unittest.TestCase):
    def test_prints_validated_url_and_digest(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "opencode-v2.rb"
            path.write_text(make_formula(), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(HELPER), str(path), X64_ASSET],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            f"https://opencode.ai/files/bin/2.3.2/{X64_ASSET}\t{'a' * 64}",
        )

    def test_fails_closed_on_invalid_formula(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "opencode-v2.rb"
            path.write_text(make_formula(version="1.19.6"), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(HELPER), str(path), X64_ASSET],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid V2 formula", result.stderr)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
