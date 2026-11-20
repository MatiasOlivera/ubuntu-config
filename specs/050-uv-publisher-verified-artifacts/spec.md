# spec.md - `050-uv-publisher-verified-artifacts`

## Context

Issue: [#50](https://github.com/MatiasOlivera/ubuntu-config/issues/50), part of
[#44](https://github.com/MatiasOlivera/ubuntu-config/issues/44).

`setup/development/uv.sh` downloads the mutable script at
`https://astral.sh/uv/install.sh` to a temp file and executes it with `sh`.
That runs remote-origin code during first-machine bootstrap with no integrity
material for the script itself, violating constitution axiom 3 and ADR 0003.

Publisher integrity research (live GitHub release `0.13.9`, inspected
2026-11-20):

- Astral publishes a maintainer-generated `<asset>.sha256` for every release
  asset, e.g. `uv-x86_64-unknown-linux-gnu.tar.gz.sha256`, containing
  `<64 hex>  <asset name>` in standard `sha256sum` format. This is
  maintainer-published integrity material covering the exact Linux artifact.
- It also publishes a combined `sha256.sum` for all release assets, GitHub's
  per-asset `digest: sha256:…` field, and GitHub Artifact Attestations
  (`gh attestation verify --repo astral-sh/uv`).
- Linux release tarballs contain `uv-<target>/uv` and `uv-<target>/uvx`
  (confirmed by listing the `0.13.9` x86_64 tarball).
- The latest-release tag is a bare version (`0.13.9`), not `v`-prefixed.
  `GET /releases/latest` returns `tag_name` and the exact asset name in one
  JSON response; the `HEAD` redirect currently points at `/tag/0.13.9`.
- No exception decision is needed: usable maintainer material exists, so
  [ADR 0007](../../docs/decisions/0007-artifact-integrity-source-priority.md)
  selects the per-asset `.sha256` file. The findings are recorded here and in
  the implementation PR; ADR 0007 already states the general source priority,
  so no new decision record is needed.

## User stories

- As a person setting up a fresh Ubuntu machine, I want uv installed from its
  checksum-verified release artifact, so setup never executes an unverifiable
  remote installer.
- As a person rerunning setup, I want an existing uv installation skipped with
  no network access, so reruns stay fast and predictable.
- As a reviewer, I want missing or mismatched integrity material to stop the
  step with a named error, so no unverified bytes are installed.

## Acceptance criteria (BDD)

```gherkin
Scenario: install the checksum-verified Linux release artifact
  Given uv is not installed
  And the publisher release provides the arch-matched artifact and its checksum
  When the uv setup step runs
  Then the artifact bytes are checked against the publisher per-asset checksum before any install
  And the verified uv and uvx executables are installed in the existing install directory
  And the step reports a successful install with the installed uv version

Scenario: skip an existing installation without network access
  Given uv is already installed and reports a version
  When the uv setup step runs
  Then the step reports that uv was skipped
  And no network request is made

Scenario: reject a tampered artifact
  Given the downloaded artifact does not match its publisher checksum
  When the uv setup step runs
  Then the step fails with a named checksum error
  And no uv executable is created or modified

Scenario: reject missing or unreadable integrity material
  Given the publisher provides no usable checksum for the selected artifact
  When the uv setup step runs
  Then the step fails with a named integrity-material error
  And no uv executable is installed

Scenario: reject a failed download or invalid archive
  Given the metadata request, artifact download or checksum download fails, or the archive is invalid
  When the uv setup step runs
  Then the step fails with a named error
  And no uv executable is installed

Scenario: reject an unsupported architecture
  Given the machine architecture has no matching Linux release artifact
  When the uv setup step runs
  Then the step fails with an error naming the unsupported architecture
  And no uv executable is installed

Scenario: keep the dispatcher and version-report contract
  Given the script is sourced by setup/install.sh or reports/versions.sh
  When install_uv or uv_version is called
  Then the same function names and output contract are honored
  And a failing install returns to the caller without disturbing its EXIT trap
```

## Constraints

- [ ] Security: the remote installer script is never downloaded or executed;
      verification is mandatory and fails closed.
- [ ] Integrity source is the per-asset maintainer-published `.sha256` file.
      If it is missing or unusable, the step fails closed with a named error;
      no GitHub-digest fallback and no self-authored hash pin are used while
      maintainer material is the selected contract.
- [ ] Latest release is resolved from GitHub's `releases/latest` API response
      (`tag_name` plus exact asset name), not by parsing an HTTP redirect.
- [ ] Preserve the `install_uv` / `uv_version` functions, the dispatcher tail,
      the skip guard, the network-free version report, and the existing
      `~/.local/bin` install location. Both `uv` and `uvx` are installed to
      preserve the upstream installer's behavior.
- [ ] The functional test `tests/setup/development/uv-test.sh` is hermetic:
      stubbed network tooling, per-test temporary directories, no system or
      network writes. `tests/test.sh` discovers it as a `*-test.sh` test.
- [ ] Out of scope: uv functionality changes, other scripts tracked in #44.

## Assumptions

- `setup/install.sh` already sources `development/uv.sh` and calls
  `step install_uv`; `reports/versions.sh` already has `src development/uv.sh`
  and `chk "uv" uv_version`. Neither file needs a change. Observed in those
  files at base tip `1b7e335`.
- Supported Linux asset mapping is `x86_64`/`amd64` →
  `uv-x86_64-unknown-linux-gnu.tar.gz`, `aarch64`/`arm64` →
  `uv-aarch64-unknown-linux-gnu.tar.gz`. Source: asset names in release
  `0.13.9`. Verification: re-check the asset list at implementation time.
- `python3` is available for JSON parsing; it is already used by other setup
  scripts and present in the Docker test image. Source:
  `setup/development/antigravity_cli_metadata.py` and `tests/Dockerfile`.
  Verification: the hermetic test runs under `./tests/test.sh` in the isolated
  container.
