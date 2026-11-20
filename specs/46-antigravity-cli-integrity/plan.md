# plan.md - `46-antigravity-cli-integrity`

## Architecture

Only `setup/development/antigravity-cli.sh` needs behavior changes. It is
already sourced by `setup/post-install.sh`; `reports/versions.sh` already
sources the script and checks `antigravity_cli_version`; the README already
lists Antigravity CLI. The new functional test is auto-discovered by
`tests/test.sh` (`tests/test.sh:144-152`).

Install flow:

1. Preserve the existing `antigravity_cli_version` skip guard. If it reports a
   version, print the current skip marker and make no network requests.
2. Map `x86_64`/`amd64` to Google's `linux_amd64` manifest and
   `aarch64`/`arm64` to `linux_arm64`. Reject other architectures with a named
   error.
3. Fetch the architecture manifest once. Parse JSON as data with Python's
   standard library; validate the version, artifact URL and any checksum before
   using them.
4. If the valid manifest contains a SHA-512 digest, download its Google-hosted
   artifact and verify it before extracting the `antigravity` binary.
5. If the valid manifest has no usable digest, fetch the GitHub release for the
   same version, select the architecture-matched `agy_cli_linux_<arch>.tar.gz`
   asset and its `sha256:` digest, then download and verify that GitHub asset.
   The publisher manifest transport or parse failing is an error and never
   enters this fallback.
6. Extract only after verification. Install the binary as
   `$HOME/.local/bin/agy`, verify it runs and reports a version, then preserve
   the existing `/usr/local/bin/agy` symlink behavior.
7. Keep temporary files private and clean them on every return path. Use a
   subshell boundary for install internals so failure does not replace the
   caller's exit trap or terminate the parent setup run.

The hermetic test stubs `curl` and `sudo`, provides fixture manifests and
archives, and uses a sandboxed `HOME`. It covers publisher SHA-512 verification,
GitHub SHA-256 fallback, source priority, tampering, absent integrity data,
manifest failures, download failures, architecture selection, skip-without-
network, and command availability. No real network or system directory is
touched.

## Data models

- Google manifest JSON: `version`, `url`, optional `sha512`.
- GitHub release JSON: matching `tag_name`, plus an exact architecture asset
  with a `sha256:<hex>` `digest` and `browser_download_url`.
- Installed binary: `$HOME/.local/bin/agy` (maintainer archive entry is named
  `antigravity`).
- Public command: `/usr/local/bin/agy` symlink, as in the current script.
- No version marker or new persistent state; `agy --version` remains the guard.

## API contracts

- Publisher manifests:
  - `https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json`
  - `https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_arm64.json`
  - Valid response observed 2026-11-19: `version`, Google Storage `url`, and
    128-hex-character `sha512`.
- GitHub fallback metadata:
  `GET https://api.github.com/repos/google-antigravity/antigravity-cli/releases/tags/<version>`.
  Require the exact version and matching release asset with a valid SHA-256
  digest; never use an unpinned `latest` lookup for this fallback.
- Runtime commands: `curl`, `python3`, `sha512sum`, `sha256sum`, `tar`, and
  standard core utilities. Python 3 is present in the vendored Ubuntu 26.04
  desktop baseline (`reports/baselines/ubuntu-26.04.1-desktop-manifest.txt:1509`).
- Existing repository interface: `install_antigravity_cli`,
  `antigravity_cli_version`, standalone `install|version` dispatcher.

## Decisions

- `docs/decisions/0007-artifact-integrity-source-priority.md` — prefer
  maintainer-published integrity material and use GitHub's SHA-256 digest only
  when the maintainer publishes no usable material. This issue applies that
  rule to Google's SHA-512 manifest; transport or parsing errors fail closed.

## Risks

- Google changes its manifest or archive layout: fail with a named error; update
  the contract and fixtures rather than weakening verification.
- The valid Google response omits its checksum and no exact GitHub release
  digest is available: fail closed without installing an artifact.
- GitHub's digest is computed by GitHub and shares the release host's trust
  boundary; this is fallback material only and retains the residual risk in
  ADR 0003.
- The existing symlink operation needs `sudo`; the functional suite stubs it,
  while the prescribed VM test covers the real install path.
