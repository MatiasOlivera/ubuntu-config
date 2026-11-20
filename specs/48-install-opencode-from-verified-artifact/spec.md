# spec.md - `48-install-opencode-from-verified-artifact`

## Context

Issue: [#48](https://github.com/MatiasOlivera/ubuntu-config/issues/48)

`setup/development/opencode.sh` currently executes the remote installer at
`https://opencode.ai/install`, which is the legacy OpenCode 1 installer. The
user's intended version is OpenCode 2. The setup step must install V2 from a
verified artifact without executing the remote installer, consistent with
constitution axiom 3 and
`docs/decisions/0003-remote-installer-integrity.md`.

The official `anomalyco/homebrew-tap` V2 formula publishes versioned Linux
artifact URLs and SHA-256 checksums. Its current version (`2.3.2`, checked
2026-11-20) includes Linux x64 baseline and arm64 artifacts. The repository
integrity policy prefers maintainer-published material and permits GitHub's
asset digest as a general fallback (`docs/decisions/0007-artifact-integrity-source-priority.md`).
This installer uses only the checksum from the V2 Homebrew formula and does
not select or fall back to a GitHub digest at runtime.

Goal: install a working OpenCode 2 CLI from a versioned release artifact only
after verifying it against the matching checksum in the official V2 formula,
while preserving the existing skip guard and dispatcher contract.

## User stories

- As a person setting up a fresh Ubuntu machine, I want OpenCode 2 installed
  without executing a remote installer script, so setup does not run unchecked
  remote code.
- As a person rerunning setup, I want an existing OpenCode installation to
  skip without network access, so setup does not silently replace it.
- As a reviewer, I want the downloaded V2 archive checked against the checksum
  in the official Homebrew formula, so altered or unverifiable bytes are
  rejected.

## Acceptance criteria (BDD)

```gherkin
Scenario: install a verified V2 release
  Given OpenCode is not installed
  And the official V2 formula lists a matching Linux artifact and SHA-256 checksum
  When the OpenCode setup step runs
  Then a working OpenCode 2 `opencode` command is installed
  And the archive is verified before it is extracted or installed
  And no remote installer script is executed

Scenario: use the formula checksum for the matching architecture
  Given the V2 Homebrew formula lists Linux x64-baseline and arm64 artifacts with checksums
  When the OpenCode setup step runs on x64 or arm64 Linux
  Then it selects the matching artifact URL and checksum from that formula

Scenario: fail when the V2 formula has no usable matching checksum
  Given the official V2 formula has no usable matching Linux artifact and checksum
  When the OpenCode setup step runs
  Then it fails with a named error
  And it does not try a GitHub release asset digest
  And no OpenCode binary is installed

Scenario: reject a tampered archive
  Given the downloaded V2 archive does not match the formula checksum
  When the OpenCode setup step runs
  Then it fails with a named verification error
  And no OpenCode binary is installed

Scenario: skip an existing installation without network
  Given `opencode --version` reports an installed version
  When the OpenCode setup step runs
  Then it reports the existing skip result
  And it makes no network request

Scenario: reject an unsupported architecture
  Given the machine architecture has no matching V2 formula artifact
  When the OpenCode setup step runs
  Then it fails with an error naming the unsupported architecture
  And no OpenCode binary is installed
```

## Constraints

- [ ] Never execute the remote installer; verify the downloaded artifact
      before extracting or installing it.
- [ ] Install OpenCode 2 using only the matching-version SHA-256 checksum in
      the official `opencode-v2` Homebrew formula. Fail closed when the formula
      has no valid matching artifact URL and checksum; do not implement GitHub
      digest fallback in this installer.
- [ ] Preserve the version-based skip guard, source-only behavior,
      `install_opencode`, `opencode_version`, and standalone dispatcher
      contract. An existing version continues to satisfy the skip guard; V1 to
      V2 migration is out of scope.
- [ ] Support Linux x64 via the formula's x64-baseline artifact and Linux arm64
      via its arm64 artifact.
- [ ] Add hermetic functional coverage in
      `tests/setup/development/opencode-test.sh`; tests use stubbed network
      tools and temporary install paths only.
- [ ] Out of scope: changing OpenCode functionality, automatically upgrading
      an existing installation, migrating an existing V1 installation, or
      changing other setup scripts tracked by #44.

## Assumptions

- The V2 formula is the official maintainer checksum source for these Linux
  artifacts. Source: `anomalyco/homebrew-tap/opencode-v2.rb` published
  versioned `opencode.ai/files/bin/2.3.2/` Linux URLs and matching SHA-256
  values on 2026-11-20. Verification: require an architecture-matched URL and
  valid checksum from the formula; absent or malformed entries fail closed.
- V2 installs to `$HOME/.opencode/bin`, matching the existing dotfile PATH
  entry. Source: current official V2 installer at
  `https://opencode.ai/v2/install` and `dotfiles/dot_zshrc`. Verification:
  install to that location and confirm the staged binary reports its version.
