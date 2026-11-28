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
    / "essentials"
    / "chezmoi_metadata.py"
)

TAG = "v2.74.2"
VERSION = "2.74.2"
PREFIX = "https://github.com/twpayne/chezmoi/releases/download/"
DIGEST = "a" * 64
ASSETS = {
    "amd64": "chezmoi_2.74.2_linux_amd64.tar.gz",
    "arm64": "chezmoi_2.74.2_linux_arm64.tar.gz",
}
CHECKSUMS = "chezmoi_2.74.2_checksums.txt"


def setUpModule():
    if not HELPER.is_file():
        raise AssertionError(f"missing metadata helper: {HELPER}")


def asset(arch, *, name=None, url=None):
    filename = name or ASSETS[arch]
    return {
        "name": filename,
        "browser_download_url": (
            url if url is not None else PREFIX + TAG + "/" + filename
        ),
    }


def release(assets=None):
    chosen = [asset("amd64"), asset("arm64"), asset("amd64", name=CHECKSUMS)]
    if assets is not None:
        chosen = assets
    return {"tag_name": TAG, "assets": chosen}


def run_helper(*args):
    return subprocess.run(
        [sys.executable, str(HELPER), *args],
        check=False,
        capture_output=True,
        text=True,
    )


def run_release(data, arch="amd64"):
    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / "release.json"
        path.write_text(json.dumps(data), encoding="utf-8")
        return run_helper("release", str(path), arch)


def run_checksum(lines, asset_name=ASSETS["amd64"]):
    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / CHECKSUMS
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return run_helper("checksum", str(path), asset_name)


class ReleaseMetadataTests(unittest.TestCase):
    def test_amd64_asset_and_urls(self):
        result = run_release(release())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            f"{VERSION}\t{ASSETS['amd64']}\t{PREFIX}{TAG}/{ASSETS['amd64']}"
            f"\t{PREFIX}{TAG}/{CHECKSUMS}",
        )

    def test_arm64_asset_and_urls(self):
        result = run_release(release(), "arm64")
        self.assertEqual(result.returncode, 0, result.stderr)
        fields = result.stdout.strip().split("\t")
        self.assertEqual(fields[0], VERSION)
        self.assertEqual(fields[1], ASSETS["arm64"])
        self.assertEqual(fields[2], PREFIX + TAG + "/" + ASSETS["arm64"])
        self.assertEqual(fields[3], PREFIX + TAG + "/" + CHECKSUMS)

    def test_rejects_bad_tag(self):
        for tag in ["2.74.2", "v2.74", "release-2.74.2"]:
            with self.subTest(tag=tag):
                data = release()
                data["tag_name"] = tag
                result = run_release(data)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_rejects_missing_or_duplicate_asset(self):
        for assets in [
            [asset("amd64", name=CHECKSUMS)],
            [asset("amd64"), asset("amd64"), asset("amd64", name=CHECKSUMS)],
        ]:
            with self.subTest(count=len(assets)):
                result = run_release(release(assets))
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_rejects_untrusted_asset_url(self):
        bad = asset("amd64", url=PREFIX + TAG + "/" + ASSETS["amd64"] + "?x=1")
        result = run_release(release([bad, asset("amd64", name=CHECKSUMS)]))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_rejects_missing_checksums_asset(self):
        result = run_release(release([asset("amd64")]))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_rejects_malformed_metadata(self):
        for data in [{}, {"tag_name": TAG}, {"tag_name": TAG, "assets": []}]:
            with self.subTest(data=data):
                result = run_release(data)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_rejects_unknown_arch(self):
        result = run_release(release(), "riscv64")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_failure_is_named_on_stderr(self):
        result = run_release({})
        self.assertIn("error: chezmoi:", result.stderr)


class ChecksumMetadataTests(unittest.TestCase):
    def test_selects_exact_asset_line(self):
        result = run_checksum(
            [
                f"{'b' * 64}  {CHECKSUMS}",
                f"{DIGEST}  {ASSETS['amd64']}",
                f"{'c' * 64}  {ASSETS['amd64']}.sbom.json",
            ]
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), DIGEST)

    def test_rejects_missing_line(self):
        result = run_checksum([f"{DIGEST}  {ASSETS['arm64']}"])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_rejects_duplicate_line(self):
        result = run_checksum(
            [f"{DIGEST}  {ASSETS['amd64']}", f"{'b' * 64}  {ASSETS['amd64']}"]
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_rejects_bad_digest(self):
        result = run_checksum([f"abc  {ASSETS['amd64']}"])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_failure_is_named_on_stderr(self):
        result = run_checksum([])
        self.assertIn("error: chezmoi:", result.stderr)


if __name__ == "__main__":
    unittest.main()
