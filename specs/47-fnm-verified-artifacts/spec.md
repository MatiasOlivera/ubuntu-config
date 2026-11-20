# spec.md - `47-fnm-verified-artifacts`

## Context

Issue: [#47](https://github.com/MatiasOlivera/ubuntu-config/issues/47)

`setup/development/fnm/install-fnm.sh` currently pipes the mutable installer at
`https://fnm.vercel.app/install` directly into Bash. That executes remote code
without integrity verification during machine setup. The goal is to install
fnm from a release artifact whose bytes are checked before installation, while
preserving the current skip behavior and setup command contract.

The maintainer's current installer source downloads the Linux release ZIP and
extracts `fnm`, but does not verify its integrity. The latest GitHub release
inspected for this specification was `v1.39.0`: its Linux assets have no
separate maintainer checksum or signature in the release assets, while GitHub's
release API provides a SHA-256 digest for each asset. The release page's
verified signature applies to the source commit; it is not an asset signature.
Under [ADR 0007](../../docs/decisions/0007-artifact-integrity-source-priority.md),
the GitHub asset digest is the allowed fallback when maintainer-published
integrity material is unavailable. The official installer behavior is visible
in [fnm's install source](https://github.com/Schniz/fnm/blob/master/.ci/install.sh#L796-L840);
the release API and assets are at
[Schniz/fnm releases](https://github.com/Schniz/fnm/releases).

## User stories

- As a person setting up a fresh Ubuntu machine, I want fnm installed from a
  verified release artifact, so that setup does not execute an unverified
  remote installer.
- As a person rerunning setup, I want an existing fnm installation to be
  skipped without network access, so that setup remains quick and predictable.
- As a reviewer, I want missing or mismatched integrity data to stop the
  install, so that unverifiable bytes are never installed.

## Acceptance criteria (BDD)

```gherkin
Scenario: install the verified Linux release artifact
  Given fnm is not installed
  And the release provides a Linux artifact and usable integrity material
  When the fnm setup step runs
  Then a working fnm binary is installed in the existing fnm binary directory
  And its bytes match the selected release artifact
  And the integrity check uses maintainer-published material when available
  And otherwise it uses the GitHub release asset SHA-256 digest
  And the step reports a successful install

Scenario: skip an existing installation without network access
  Given fnm is already installed and reports a version
  When the fnm setup step runs
  Then the step reports that fnm was skipped
  And no network request is made

Scenario: reject a tampered artifact
  Given the downloaded release artifact does not match its selected integrity
      material
  When the fnm setup step runs
  Then the step fails with a named integrity error
  And the installed fnm binary is not created or modified

Scenario: reject missing integrity material
  Given neither the maintainer nor GitHub provides usable integrity material
      for the selected artifact
  When the fnm setup step runs
  Then the step fails with a named integrity-data error
  And no fnm binary is installed

Scenario: reject a failed download or invalid archive
  Given the artifact download fails or the artifact cannot be extracted
  When the fnm setup step runs
  Then the step fails with a named error
  And no fnm binary is installed

Scenario: reject an unsupported architecture
  Given the machine architecture has no supported Linux release artifact
  When the fnm setup step runs
  Then the step fails with an error naming the unsupported architecture
  And no fnm binary is installed
```

## Constraints

- [ ] Security: the remote `install` script is never downloaded or executed;
      integrity verification is mandatory and fails closed.
- [ ] Integrity source priority follows
      [ADR 0007](../../docs/decisions/0007-artifact-integrity-source-priority.md):
      maintainer-published material first, GitHub asset SHA-256 digest as
      fallback, otherwise fail closed. Never use a self-authored hash pin.
- [ ] Preserve the current `fnm_version` skip guard, dispatcher behavior,
      installation location, and `unzip` dependency unless implementation
      evidence requires a spec update.
- [ ] The functional test `tests/setup/development/fnm-test.sh` is hermetic:
      stub network tooling, use temporary directories, and make no system
      writes. `tests/test.sh` discovers it as a `*-test.sh` test.
- [ ] Out of scope: fnm functionality, Node version selection, and changes to
      other remote-installer setup paths tracked under issue #44.

## Assumptions

- At implementation time, inspect fnm's official release and distribution
  channels again for maintainer-published checksums or signatures covering the
  exact Linux artifact. Source: the maintainer installer and `v1.39.0` release
  inspected while drafting this spec. Verification: repeat the inspection for
  the release selected by the install flow and record the artifact/version,
  channels checked, material found, and any GitHub-digest fallback in the PR.
