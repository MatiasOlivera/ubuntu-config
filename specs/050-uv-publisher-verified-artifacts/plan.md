# plan.md - `050-uv-publisher-verified-artifacts`

## Architecture

Three code files change: `setup/development/uv.sh`, a new
`setup/development/uv_release.py` helper, and the new hermetic test; the
wiring is already in place. `setup/install.sh`
sources `development/uv.sh` and calls `step install_uv`, and
`reports/versions.sh` has both `src development/uv.sh` and
`chk "uv" uv_version` (observed at base tip `1b7e335`). No changes to those
files, to `README.md`, or to any ADR.

`install_uv()` keeps its shape: call `uv_version`, print the unchanged skip
message and return 0 if installed; otherwise create a private `mktemp -d`, run
the verification/install work in a subshell so `install.sh`'s EXIT trap stays
intact, remove the temp directory, and return the subshell's status.

The verified path, inside `uv_install_verified "$tmp"`:

1. Map `uname -m` to the Linux target suffix; reject other architectures by
   name before any network call. Check the required commands (`curl`, `tar`,
   `sha256sum`, `python3`).
2. Fetch `https://api.github.com/repos/astral-sh/uv/releases/latest` once with
   `curl -fsSL`. The `uv_release.py` helper parses that one response and
   emits `tag_name` only if `assets[].name` contains the expected artifact
   name. An empty result is a named error, so tag, asset and checksum all
   refer to the same release.
3. Build `https://github.com/astral-sh/uv/releases/download/<tag>/` and
   download `<asset>.sha256` then `<asset>` with `curl -fsSL` into the temp
   directory. Both downloads are mandatory; neither is parsed as code.
4. Verify with `sha256sum -c <asset>.sha256` from inside the temp directory
   (the published file has the form `<64 hex>  <asset>`). Fail closed on a
   missing checksum file, a missing checksum line, a mismatch, or a failed
   command. Only verified bytes are extracted.
5. Extract the tarball into the temp directory, require `uv-<target>/uv` and
   `uv-<target>/uvx`, and check that `uv --version` runs.
6. Stage both binaries in `$HOME/.local/bin` as `.part.$$` files, then move
   them into place. Any failure cleans staged files and reports a named error;
   a failure before this point leaves any existing installation untouched.
   Print `installed: uv <version> to <dir>/uv` on success.

`uv_version()` stays exactly as it is: a network-free, subshelled
`$HOME/.local/bin` PATH prepend used by both the skip guard and the report.

`tests/setup/development/uv-test.sh` is a black-box hermetic suite in the
style of `copilot-test.sh`: stub `curl` (fixture release JSON, `.sha256`, and
a tarball built with real `tar`/`sha256sum`), stub `uname` and a failing `uv`
on PATH, sandbox `HOME`/`TMPDIR`/install dir, and assert only exit codes,
stdout/stderr markers, files, and the curl call log. Real `python3`, `tar`,
`sha256sum` and `install` are used. The test fails against the current
remote-script installer, before the script is changed.

## Data models

None. The release JSON and checksum file are transient metadata; no persisted
format or state file is introduced.

## API contracts

- `GET https://api.github.com/repos/astral-sh/uv/releases/latest`, with
  `Accept: application/vnd.github+json`; expects `tag_name` and
  `assets[].name`. The expected asset must be listed; otherwise fail closed.
- `GET https://github.com/astral-sh/uv/releases/download/<tag>/<asset>` and
  `.../<asset>.sha256`. The checksum file is standard `sha256sum` output with
  the asset's own filename as the checked path.
- Architecture mapping: `x86_64`/`amd64` →
  `uv-x86_64-unknown-linux-gnu.tar.gz`; `aarch64`/`arm64` →
  `uv-aarch64-unknown-linux-gnu.tar.gz`. Tarball layout:
  `uv-<target>/uv` and `uv-<target>/uvx`.
- Observable errors name the cause: unsupported architecture, missing
  command, metadata unavailable/asset absent, checksum unavailable, checksum
  mismatch, invalid tarball, missing binary, binary failed to run, or install
  failure. Errors go to stderr and return non-zero from `install_uv`.
- Unchanged observable contracts: skip message
  `skip: uv already installed (<version>)`; version report from `uv_version`.

## Decisions

- Use the per-asset maintainer `.sha256` as the sole integrity source.
  [ADR 0003](../../docs/decisions/0003-remote-installer-integrity.md) forbids
  remote script execution;
  [ADR 0007](../../docs/decisions/0007-artifact-integrity-source-priority.md)
  prefers maintainer material, which is present. No GitHub-digest fallback,
  no self-authored hash pin, no exception record.
- Resolve the tag from the GitHub `releases/latest` API rather than the
  `Location` header of a redirect. Human decision after noting a redirect can
  point somewhere other than a tag; the API exposes `tag_name` explicitly.
  `python3` is already used by `setup/development/antigravity_cli_metadata.py`
  and installed in `tests/Dockerfile`.
- Install both `uv` and `uvx` to preserve upstream installer behavior. Human
  decision; both binaries are present in the release tarball.
- Record the publisher findings in the spec and PR description, not in a new
  ADR. Human decision; ADR 0007 already carries the general source-priority
  rule.

## Risks

- Upstream renames assets, changes the tarball layout, or stops publishing
  `.sha256` files → the step fails closed with a named error; update the
  mapping only after re-checking the official release.
- GitHub API rate limiting or an unavailable release endpoint → named
  metadata error, no install. This is a new network dependency for this step,
  replacing the previous installer download.
- A verified-but-unrunnable binary (bad mount, missing loader) is caught by the
  `uv --version` smoke check before staging.
- A failure between the two final moves could leave `uv` present without
  `uvx`; staging both under `.part.$$` and moving them together minimizes that
  window, and the version guard means a rerun would not heal it automatically.
- Reused-VM reruns are covered by the unchanged skip guard; the hermetic test
  asserts the skip path makes no curl call.

## Assumptions

- The Linux asset mapping and tarball layout come from live inspection of
  release `0.13.9` on 2026-11-20 (GitHub release API, raw `.sha256` file, and
  `tar -tzf` listing). Verification: re-check the selected release at
  implementation time; any change is a named failure, not a silent install.
- `python3` is present in the build and test images
  (`setup/development/antigravity_cli_metadata.py`, `tests/Dockerfile:3`).
  Verification: the functional test runs under `./tests/test.sh` and the
  isolated compose test in CI.
- `tests/test.sh` discovers every `*-test.sh` under `tests/`
  (`tests/test.sh:144-152`), so the new file runs in both static and Docker
  verification without wiring changes.
