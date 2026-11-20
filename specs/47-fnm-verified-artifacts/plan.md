# plan.md - `47-fnm-verified-artifacts`

## Architecture

Only the fnm install implementation and its hermetic functional test need to
change. `setup/post-install.sh` already sources this script and calls
`install_fnm`; the function name, `fnm_version` guard, dispatcher, and
`~/.local/share/fnm` location stay intact.

After the skip guard, the install path will:

1. Map the supported Linux machine architecture to the publisher's release
   asset (`fnm-linux.zip`, `fnm-arm64.zip`, or `fnm-arm32.zip`). Reject other
   architectures with a named error before installing dependencies.
2. Install the existing `unzip` dependency, then check required commands.
3. Request the latest release metadata once from GitHub's `Schniz/fnm` release
   API. Select the exact expected asset from that response so tag, download
   URL, and digest all refer to the same release.
4. Download the selected ZIP to a temporary directory, verify it with
   `sha256sum`, and only then extract the expected `fnm` executable. Accept the
   root or asset-directory layout handled by the official installer; reject a
   missing executable or invalid archive.
5. Stage the executable in the destination filesystem, set its executable bit,
   and move it into place only after verification and extraction succeed. Clean
   temporary files on success and failure. A verification failure leaves an
   existing binary untouched.

No changes are needed to `setup/post-install.sh`, `reports/versions.sh`, or
`README.md`: the package remains in the same phase and retains the same public
function and install path.

## Data models

None. The release API JSON is consumed as transient metadata only.

## API contracts

- Request: one unauthenticated `GET
  https://api.github.com/repos/Schniz/fnm/releases/latest` per fresh install.
- Selection: `tag_name` plus the asset whose name exactly matches the selected
  architecture. The selected asset must include `browser_download_url` and a
  `sha256:` digest containing exactly 64 hexadecimal characters when GitHub
  fallback is used.
- Integrity: verify the downloaded ZIP bytes before extraction. Do not install
  a partial download, accept missing integrity data, or use a self-recorded
  hash.
- Supported Linux mapping: `x86_64`/`amd64` → `fnm-linux.zip`;
  `aarch*`/`arm64`/`armv8*` → `fnm-arm64.zip`; `arm`/`armv7*` →
  `fnm-arm32.zip`.
- Observable failures name the cause: unsupported architecture, release
  metadata unavailable, asset absent, integrity data absent or malformed,
  artifact download failure, checksum mismatch, invalid ZIP, or missing `fnm`
  executable.

## Decisions

- Integrity source priority follows accepted
  [ADR 0007](../../docs/decisions/0007-artifact-integrity-source-priority.md).
  The inspected release has no maintainer-published checksum or asset
  signature, so GitHub's per-asset SHA-256 digest is the fallback for this
  change. Recheck this before implementation; if it changes, follow ADR 0007
  and update the plan. Record the artifact/version, channels checked, and
  fallback reason in the implementation PR as required by the `install-package`
  skill. No integrity exception is needed while the GitHub digest remains
  available.
- Use the GitHub latest-release API response as the single source for the
  release tag, selected asset URL, and digest. This avoids resolving `latest`
  separately for metadata and artifact downloads.
- Use Python 3's standard-library JSON parser rather than adding `jq` as a
  dependency. Python 3 is already part of the repository's Ubuntu setup and is
  used by existing setup scripts that parse release metadata.

## Risks

- GitHub's digest confirms the bytes GitHub hosts; it does not independently
  prove maintainer intent. A compromise before upload could affect both. This
  is the explicit fallback trade-off in ADR 0007.
- The GitHub API may be unavailable or rate-limited. The step must fail with a
  useful message and install nothing.
- Release asset names or ZIP layout may change. Exact-name selection and
  fail-closed archive checks make that visible; update the mapping only after
  confirming the new official release contract.
- The existing dependency function installs `unzip` before fetching the
  artifact. That behavior is retained; a failed verification still leaves fnm
  itself uninstalled or unchanged.

## Assumptions

- `setup/development/fnm/install-fnm.sh` defines the current install path,
  version guard, and `unzip` dependency; `setup/post-install.sh` sources it and
  calls `install_fnm`. `setup/essentials/pip.sh` installs `python3-pip`, and
  `setup/install.sh` invokes that essentials step before post-install.
- The latest release API response inspected while planning was `v1.39.0`; it
  listed `fnm-linux.zip`, `fnm-arm64.zip`, and `fnm-arm32.zip` with `sha256:`
  digests and no separate checksum asset ([release API](https://api.github.com/repos/Schniz/fnm/releases/latest)).
  The [official installer source](https://github.com/Schniz/fnm/blob/master/.ci/install.sh#L736-L840)
  maps Linux architectures to these names and extracts either `fnm` or
  `<asset-name>/fnm` without checking integrity. The release page's verified
  signature is for the source commit, not the release ZIP. Recheck these details
  against the selected release during implementation.
- `tests/test.sh` discovers and runs every `*-test.sh` under `tests/`; the
  isolated compose test runs that suite inside its Ubuntu container.
  `tests/Dockerfile` does not install `unzip`, so the functional test must stub
  extraction (for example, with Python's standard library) and write only
  under its temporary directory and sandboxed `HOME`.
