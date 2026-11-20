# spec.md - `46-antigravity-cli-integrity`

## Context

Issue: [#46](https://github.com/MatiasOlivera/ubuntu-config/issues/46)

`setup/development/antigravity-cli.sh` currently pipes Google's remote
`install.sh` into Bash. That executes mutable remote code during setup without
checking its integrity, contrary to constitution axiom 3 and
`docs/decisions/0003-remote-installer-integrity.md`.

Google's official CLI updater publishes architecture-specific JSON manifests
with a version, artifact URL, and SHA-512 digest. Live manifests for Linux x64
and ARM64 both returned version `1.5.13` and a `sha512` field on 2026-11-19.
The official CLI repository also documents permanent GitHub release artifact
URLs. The selected policy is to prefer maintainer-published checksums or
signatures; if the maintainer publishes none for the artifact, fall back to a
GitHub-published release asset digest. If neither source provides usable
integrity material, installation must fail closed.

Goal: install the CLI without executing the remote installer, verify the
archive before installing it, and preserve the existing skip guard, command
availability, and dispatcher contract.

## User stories

- As a person running setup on a fresh Ubuntu machine, I want the Antigravity
  CLI installed and available as `agy`, so that I can use it after setup.
- As a person rerunning setup, I want an existing CLI to skip installation
  without network access, so that setup does not silently replace it.
- As a reviewer, I want the archive checked against the strongest integrity
  material the maintainer publishes, with GitHub's digest as the fallback, so
  that setup installs only verifiable bytes.

## Acceptance criteria (BDD)

```gherkin
Scenario: install using maintainer-published integrity material
  Given the official maintainer manifest lists a Linux artifact and its digest
  When the Antigravity CLI setup step runs
  Then the matching artifact is installed as `agy`
  And its bytes are verified against the maintainer-published digest
  And no remote installer script is executed
  And the existing `/usr/local/bin/agy` command remains available

Scenario: prefer maintainer material when GitHub also exposes a digest
  Given both the maintainer and GitHub publish integrity material for the artifact
  When the Antigravity CLI setup step runs
  Then the maintainer-published material is used for verification

Scenario: fall back to GitHub digest when maintainer publishes no integrity material
  Given the maintainer publishes no usable checksum or signature for the artifact
  And GitHub publishes a SHA-256 digest for the matching release asset
  When the Antigravity CLI setup step runs
  Then the artifact is verified against GitHub's digest before installation

Scenario: fail closed when no integrity material is available
  Given neither the maintainer nor GitHub publishes usable integrity material
  When the Antigravity CLI setup step runs
  Then the step fails with a named error
  And no CLI binary is installed

Scenario: fail closed when the maintainer manifest cannot be used
  Given the maintainer manifest is unreachable or malformed
  When the Antigravity CLI setup step runs
  Then the step fails with a named error
  And it does not silently fall back to GitHub's digest
  And no CLI binary is installed

Scenario: reject a tampered archive
  Given the downloaded archive does not match the selected published digest
  When the Antigravity CLI setup step runs
  Then the step fails with a named verification error
  And no CLI binary is installed

Scenario: already installed skips without network
  Given `agy --version` reports an installed CLI version
  When the Antigravity CLI setup step runs
  Then it reports the existing skip result
  And it makes no network request

Scenario: unsupported architecture fails clearly
  Given the machine architecture has no supported Linux artifact
  When the Antigravity CLI setup step runs
  Then it fails with an error naming the unsupported architecture
  And no CLI binary is installed
```

## Constraints

- [ ] Security: do not execute remote installer scripts; verify the downloaded
      archive before extracting or installing it.
- [ ] Integrity source order: maintainer-published checksum/signature first;
      GitHub release asset digest only when the maintainer publishes no usable
      integrity material; fail closed if neither source has one. An unreachable
      or malformed maintainer integrity endpoint is an error, not evidence that
      no publisher integrity material exists, and must not trigger fallback.
- [ ] Rerun safety: retain the version-based skip guard and do not fetch
      metadata or artifacts when it succeeds.
- [ ] Contract: preserve `install_antigravity_cli`, `antigravity_cli_version`,
      the standalone dispatcher interface, and `/usr/local/bin/agy` availability.
- [ ] Hermetic functional coverage belongs in
      `tests/setup/development/antigravity-cli-test.sh`; tests must not use the
      network or write system directories.
- [ ] Support Linux x86_64 and aarch64 when the maintainer publishes matching
      artifacts; unsupported architectures fail closed.
- [ ] Out of scope: changing Antigravity CLI behavior or adding an automatic
      upgrade path for an already-installed CLI.
