# spec.md - `06-copilot-integrity-check`

## Context

Issue: #6

`setup/development/copilot.sh` installs GitHub Copilot CLI by piping a remote
installer script (`https://gh.io/copilot-install`) straight into `bash`. The
served file is mutable branch content with no local pinning, GitHub publishes no
checksum or signature for it, and there is no `pipefail` — a failed or
truncated download still executes whatever bytes arrived. If the publisher or
the delivery path is compromised, arbitrary code runs on the setup host one
step from root (the sudo keepalive is live during `setup/install.sh`), with SSH
keys, the keyring, and any exported GitHub token in reach. HTTPS alone does not
pin content. The goal is to remove the unverifiable-remote-code execution
surface, not to defend against every publisher compromise.

## User stories

- As a person running the setup on a fresh Ubuntu machine, I want the Copilot
  CLI install to execute no remote script code, so that a compromise of the
  publisher's delivery path cannot silently run arbitrary commands on my host.
- As a person re-running the setup, I want the step to remain rerun-safe, so
  that an already-installed Copilot is skipped without touching the network.
- As a reviewer of this repo, I want integrity verification to fail closed, so
  that a tampered, truncated, or checksum-less artifact never lands on disk and
  the failure is loud rather than partial.

## Acceptance criteria (BDD)

```gherkin
Scenario: verified fresh install
  Given Copilot is not installed on the machine
  When the setup Copilot step runs with network access to GitHub releases
  Then a working `copilot` binary is installed
  And the installed binary is byte-identical to the release artifact whose
      checksum the publisher published
  And the run reports a successful verified install

Scenario: already installed skips without network
  Given Copilot is already installed and reports a version
  When the setup Copilot step runs
  Then the step reports it skipped the install
  And no download is attempted

Scenario: tampered artifact is rejected
  Given the delivered release artifact does not match the published checksum
  When the setup Copilot step runs
  Then the step fails
  And no Copilot binary is installed or modified

Scenario: missing checksum is rejected
  Given the publisher's checksum file does not contain a line for the artifact
      being installed
  When the setup Copilot step runs
  Then the step fails with a message naming the missing checksum
  And nothing is installed

Scenario: interrupted download is rejected
  Given the download fails partway (server error or truncated transfer)
  When the setup Copilot step runs
  Then the step fails
  And nothing is installed

Scenario: unsupported machine
  Given the machine's OS or CPU architecture has no published release artifact
  When the setup Copilot step runs
  Then the step fails with a message naming the unsupported OS or architecture
  And nothing is installed

Scenario: failure is contained to its step
  Given Copilot integrity verification fails for any reason
  When the full `setup/install.sh` run executes
  Then only the Copilot step reports the failure
  And later setup steps still run
```

## Constraints

- [ ] Security: no remote script is ever parsed or executed; only a release
      artifact verified against the publisher's own checksum is installed, and
      only the Copilot binary from it.
- [ ] Security: every verification step is mandatory and fail-closed — a
      missing checksum file, a missing checksum line, a mismatch, an invalid
      archive, or a missing binary in the archive all abort the step.
- [ ] Rerun-safe and source-only per AGENTS.md: the script defines its
      install/version functions without running them when sourced; standalone
      execution keeps the existing dispatcher contract.
- [ ] Integration points: `setup/install.sh` step and `reports/versions.sh`
      rows keep working unchanged; the functional test
      `tests/setup/development/copilot-test.sh` runs hermetically (stubbed
      network, temp `PREFIX`, no system writes) and is picked up by
      `./tests/test.sh` automatically.
- [ ] Support matrix: `copilot-linux-x64`, `copilot-linux-arm64`,
      `copilot-darwin-x64`, `copilot-darwin-arm64` artifacts.
- [ ] Install location: system-wide `/usr/local/bin` by default (sudo is
      already kept alive during `setup/install.sh`), overridable via the
      installer's documented `PREFIX` knob.
- [ ] Failure semantics: a verification failure fails the step loudly and
      lets the rest of the run continue — same per-step behavior as today; no
      whole-run abort is introduced.
- [ ] Version semantics: always install the latest published release at
      run time; no pinning mechanism. The skip guard means an existing
      installation is never silently upgraded.
- [ ] Out of scope: the same `curl | bash` pattern in other scripts
      (`cursor.sh`, `antigravity-cli.sh`, `fnm/install-fnm.sh`, `opencode.sh`,
      `ollama.sh`, `uv.sh`) — noted as follow-up, issue #6 covers Copilot only.

## Assumptions

- GitHub keeps publishing `SHA256SUMS.txt` in every copilot-cli release with
  standard `sha256sum -c` line format. Source: verified live against tag
  `v1.0.105` on 2026-11-04 (`gh release view` + download of the sums file).
  Verification step: the functional test fails loudly if the line format
  changes; the fail-closed checksum-line lookup turns absence into an error.
- A release-asset name is stable across releases (`copilot-<platform>-<arch>.tar.gz`).
  Source: same live check of v1.0.105 assets. Verification step: the
  "missing checksum is rejected" scenario covers a renamed asset.
