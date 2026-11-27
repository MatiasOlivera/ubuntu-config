# spec.md - `090-bitwarden-cli-verified-artifact`

## Context

Issue: [#90](https://github.com/MatiasOlivera/ubuntu-config/issues/90).

Setup installs the Bitwarden CLI (`bw`) with snap, the second-lowest rung of
[ADR 0008](../../docs/decisions/0008-install-method-priority.md). ADR 0003
requires integrity material before setup installs third-party code, and ADR 0007
sets the source priority for that material. Bitwarden publishes standalone CLI
release archives for Linux (amd64 and arm64); these are the same bytes its snap
wraps. The CLI has no Ubuntu or vendor apt package, so the checksum-verified
release-artifact rung is the highest available one.

Changes decided during planning: install the commercial (`bit`) build for
parity with the current snap; select the newest CLI release at install time so
updates do not need a manual version bump; leave any existing snap installation
and its local vault configuration untouched; keep ADR 0008's rung order and the
integrity rules unchanged. The ADR-order question raised in discussion is not
part of this issue.

This change moves only the Bitwarden CLI install to the verified-artifact rung.
It does not migrate any other application, add an integrity-exception entry, or
change an existing decision record.

## User stories

- As a person setting up a fresh workstation, I want `bw` installed from the
  publisher's release archive so that the tool reading my vault is the
  publisher's bytes.
- As a maintainer, I want the step to fail loudly when integrity material is
  missing or does not match, so setup never silently installs unverified code.
- As a person re-running setup, I want an already-installed `bw` skipped, so
  reruns stay non-interactive and do not repeat downloads.
- As a person whose shell scripts read the vault, I want `bw` callable from a
  plain non-login shell once setup has finished.
- As a maintainer, I want the versions report to show the installed CLI version
  from the new install, so the report stays accurate.
- As a person who already has the snap-installed CLI, I want my existing vault
  configuration left intact.

## Acceptance criteria (BDD)

```gherkin
Scenario: Fresh machine installs a verified Bitwarden CLI
  Given a fresh Ubuntu machine with no Bitwarden CLI installed
  And the publisher has a current CLI release for this machine's architecture
  When setup runs the Bitwarden CLI install step
  Then the CLI is installed and reports its version
  And the installed bytes match the publisher release's integrity material

Scenario: Missing or mismatched integrity material
  Given a publisher release is reachable but its integrity material is absent or does not match the download
  When setup runs the Bitwarden CLI install step
  Then the step fails with a named error
  And no CLI binary is installed or replaced

Scenario: Publisher release metadata is unreachable
  Given the release metadata cannot be downloaded
  When setup runs the Bitwarden CLI install step
  Then the step fails with a named error
  And no CLI binary is installed or replaced

Scenario: Rerun skips an installed CLI
  Given the verified Bitwarden CLI is already installed
  When setup runs the Bitwarden CLI install step again
  Then setup reports the CLI as already installed
  And no release metadata or artifact is downloaded

Scenario: Unsupported architecture
  Given this machine's architecture has no publisher CLI release artifact
  When setup runs the Bitwarden CLI install step
  Then the step fails with a named error
  And no CLI binary is installed or replaced

Scenario: CLI is callable from a non-interactive shell
  Given setup has installed the verified Bitwarden CLI
  When a script invokes bw from a plain non-login shell
  Then the command runs and reports the installed version

Scenario: Versions report sees the new install
  Given the verified Bitwarden CLI is installed
  When the versions report is generated
  Then it lists the Bitwarden CLI with the installed version

Scenario: An existing snap install is preserved
  Given bw was previously installed by snap with local vault configuration
  When setup runs the verified Bitwarden CLI install step
  Then the snap installation and its configuration remain intact
  And ordinary shells find the verified binary first
```

## Constraints

- [ ] Integrity: prefer maintainer-published material; when none is published
      for the release asset, use GitHub's release-asset SHA-256 digest as
      ADR 0007's documented fallback, and record that reason in the PR. Never
      use a self-authored hash pin. Fail closed on missing or mismatching
      material.
- [ ] The archive is verified before its binary is staged or installed; a
      failed step leaves no partially installed CLI.
- [ ] Reruns are idempotent and non-interactive on a fresh machine; the skip
      guard runs before any network access.
- [ ] Support amd64 and arm64; install the commercial (`bit`) build that the
      existing snap wraps.
- [ ] Do not remove, disable or rewrite an existing snap install or its data.
- [ ] No changes to ADR 0003, 0007 or 0008, `docs/integrity-exceptions.md`,
      another application's install method, or setup ordering.
- [ ] Hermetic functional tests stub network and system commands;
      `./tests/test.sh` passes.

## Assumptions

- Bitwarden's `cli-v*` GitHub releases publish `bw-bit-linux-<version>.zip` and
  `bw-bit-linux-arm64-<version>.zip`, whose archive root contains an executable
  `bw`. Source: `bitwarden/clients` release asset lists and
  `.github/workflows/build-cli.yml` (fetched 2026-11-26). Verification: re-check
  the release assets and archive layout before writing the install step.
- CLI release assets have no separate maintainer checksum file, so the GitHub
  release-asset digest is the fallback source. Source: expanded asset lists for
  `cli-v2026.11.0` and `cli-v2026.11.1` (fetched 2026-11-26). Verification:
  re-check the assets before implementation; if a maintainer checksum appears,
  use it instead of the digest.
- GitHub exposes a SHA-256 digest per release asset. Source: the `sha256:` value
  shown on each release asset and the existing GitHub-fallback parser in
  `setup/development/antigravity_cli_metadata.py`. Verification: confirm the
  digest field in a live release response during implementation.
- `bw -v` prints a single-line version. Source: the Version Test step in
  Bitwarden's `build-cli.yml` (fetched 2026-11-26). Verification: run it against
  the installed binary in the e2e VM.
- Ubuntu puts `/usr/local/bin` ahead of `/snap/bin` on PATH. Source: standard
  Ubuntu PATH ordering. Verification: confirm in the e2e VM that the verified
  binary wins on a machine with both installs.
