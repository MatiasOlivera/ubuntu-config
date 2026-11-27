# spec.md - `093-chezmoi-verified-artifact`

## Context

Issue: [#93](https://github.com/MatiasOlivera/ubuntu-config/issues/93).

Setup installs chezmoi by fetching `get.chezmoi.io` and piping it into `sh`
(`setup/essentials/chezmoi.sh`). [ADR 0008](../../docs/decisions/0008-install-method-priority.md)
says remote install scripts are not a rung and that executing them is allowed
only through the exception path; [ADR 0003](../../docs/decisions/0003-remote-installer-integrity.md)
forbids unverifiable execution on the setup path. This issue is one of the
follow-ups ADR 0008 deliberately left open.

The publisher ships the same tool as release archives for Linux (amd64 and
arm64) with a per-release checksum file, so the checksum-verified release
artifact rung is available. Ubuntu's stable suites do not carry chezmoi and the
publisher documents no apt repository, so the two higher distribution rungs are
not available. An exception entry is not justified: verifiable material exists.

Decisions settled with the issue owner during planning: pick the newest release
at install time (no manually pinned version), keep the installed binary at
`/usr/local/bin/chezmoi` so `install.sh` can invoke it from a non-interactive
shell, and leave ADR 0003/0007/0008, the exception register, other applications'
install methods, setup ordering and dotfiles untouched. Rung 3 is vendor-native
rather than apt-managed; putting chezmoi on an apt update path is not achievable
here and is outside this issue's scope.

## User stories

- As a person setting up a fresh workstation, I want chezmoi installed from the
  publisher's release archive so that the tool applying my dotfiles is the
  publisher's bytes.
- As a maintainer, I want an install step that fails loudly when the publisher's
  integrity material is missing or does not match, so setup never silently
  installs unverified code.
- As a person re-running setup, I want an already-installed chezmoi skipped, so
  reruns stay non-interactive and do not repeat downloads.
- As a person running plain shell scripts, I want `chezmoi` callable from a
  non-login shell once setup has finished, because `install.sh` uses it that way.
- As a maintainer, I want the versions report to show the installed chezmoi
  version, so the report stays accurate.
- As a maintainer on an arm64 machine, I want the publisher's arm64 artifact
  selected, so the install works on both supported architectures.

## Acceptance criteria (BDD)

```gherkin
Scenario: Fresh machine installs a verified chezmoi
  Given a fresh Ubuntu machine with no chezmoi installed
  And the publisher has a current release with integrity material for this machine's architecture
  When setup runs the chezmoi install step
  Then chezmoi is installed and reports its version
  And the installed bytes match the publisher's integrity material
  And no remote installer script is fetched or executed

Scenario: Missing or mismatched integrity material
  Given the publisher's release is reachable but its integrity material is absent or does not match the download
  When setup runs the chezmoi install step
  Then the step fails with a named error
  And no chezmoi binary is installed or replaced

Scenario: Publisher release metadata is unreachable
  Given the release metadata cannot be downloaded
  When setup runs the chezmoi install step
  Then the step fails with a named error
  And no chezmoi binary is installed or replaced

Scenario: Rerun skips an installed chezmoi
  Given chezmoi is already installed by this setup
  When setup runs the chezmoi install step again
  Then setup reports chezmoi as already installed
  And no release metadata or artifact is downloaded

Scenario: Unsupported architecture
  Given this machine's architecture has no publisher release artifact
  When setup runs the chezmoi install step
  Then the step fails with a named error
  And no chezmoi binary is installed or replaced

Scenario: chezmoi is callable from a non-interactive shell
  Given setup has installed the verified chezmoi
  When a script invokes chezmoi from a plain non-login shell
  Then the command runs and reports the installed version

Scenario: Versions report sees the new install
  Given the verified chezmoi is installed
  When the versions report is generated
  Then it lists chezmoi with the installed version
```

## Constraints

- [ ] Prefer maintainer-published integrity material for the exact artifact.
      Never use a self-authored hash pin or the exception path. Fail closed on
      missing, malformed or mismatching material.
- [ ] The archive is verified before its binary is staged or installed; a
      failed step leaves no partially installed chezmoi.
- [ ] No remote install script is executed; only publisher release artifacts
      and their integrity material are downloaded.
- [ ] Select the newest publisher release at install time, not a pinned
      version constant; reruns stay idempotent and non-interactive, with the
      skip guard before any network access.
- [ ] Install to `/usr/local/bin/chezmoi` and keep it callable from a plain
      non-login shell. Support amd64 and arm64.
- [ ] No changes to ADR 0003, 0007 or 0008, `docs/integrity-exceptions.md`,
      another application's install method, setup ordering or dotfiles.
- [ ] Hermetic functional tests stub network and system commands;
      `./tests/test.sh` passes, including the Docker and Multipass checks for
      an install-path change.

## Assumptions

- Each chezmoi release publishes `chezmoi_<version>_checksums.txt` with an
  entry covering `chezmoi_<version>_linux_<arch>.tar.gz`. Source: the `v2.74.2`
  asset list and checksum file fetched from GitHub on 2026-11-26; the install
  page's "Verify your download" section. Verification: re-check the assets and
  checksum file for the current release during implementation; fail closed if
  the material is absent.
- The Linux archive contains a top-level `chezmoi` binary. Source: chezmoi's
  "Download a pre-built binary" documentation and the release asset list
  (fetched 2026-11-26). Verification: extract it in the hermetic test and run
  it in the e2e VM.
- `chezmoi --version` prints exactly one version line. Source: the existing
  `chezmoi_version()` in `setup/essentials/chezmoi.sh`. Verification: the
  hermetic version assertion and the versions report in the e2e VM.
- GitHub's `releases/latest` response is newest-first and the global latest
  release is the one to install (chezmoi publishes a single product, unlike
  the multi-product repositories handled by other scripts). Source: GitHub
  REST releases contract and `v2.74.2` being marked latest on 2026-11-26.
  Verification: read the live response during implementation; if the shape
  changes, fail closed and revisit before coding.
- Ubuntu's stable suites and the publisher provide no higher rung. Source:
  packages.ubuntu.com search for `chezmoi` and the publisher's install page,
  both read 2026-11-26 (Ubuntu lists chezmoi only in the development suite
  `tenacious`; the install page lists distro packages but no apt repository).
  Verification: re-check both before implementation; if a vendor apt
  repository appears, escalate before writing code.
