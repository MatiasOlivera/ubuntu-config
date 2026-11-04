# Remote Installer Execution Integrity

- Status: proposed
- Deciders: Matias Olivera
- Date: 2026-11-04

## Context and Problem Statement

Setup scripts install third-party tools by piping publisher-hosted install
scripts straight into a shell (`curl … | bash`). The served script is mutable
content behind a redirect hop, publishers ship no checksum or signature for
the script itself, and without `pipefail` even a truncated download executes.
The script then runs in the most privileged window the machine will ever have:
during first-machine bootstrap, with a live sudo keepalive, SSH keys, a
keyring, and exported `GITHUB_TOKEN` values in reach.

Choice: what integrity standard must code executed during setup meet, and
where does that obligation bind?

## Decision Drivers

- Constitution axiom 3: the setup path must never run code it cannot hold to
  a publisher's integrity material.
- Publishers of these tools ship integrity material for release *artifacts*,
  but not for their install scripts.
- Setup runs unattended on fresh machines; a degraded check must fail loudly,
  not silently continue.
- The repo is a personal environment; defense goals are bounded: remove
  unverifiable execution, not solve full supply-chain security.
- Every added moving part in a bootstrap path is itself attack surface and
  maintenance load.

## Considered Options

| Option                                       | Outcome                                                                                                                          | Cost                                                            |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| Execute publisher install script (`curl \| bash`) | Rejected — executes code with no integrity material; unbounded blast radius on compromise.                     | Zero today; total on compromise                                  |
| Hash-pin the install script, verify before executing | Rejected — no publisher hash exists, so pins are self-recorded (TOFU); upstream edits installers weekly, so every bump demands re-audit; a matched pin still executes remote-origin code. | Per-release audit loop; breaks silently useful installs           |
| Install checksum-verified release artifact   | **Chosen** — publisher-published checksums exist for artifacts (e.g. `SHA256SUMS.txt` per copilot-cli release); no remote script is parsed at all. | Per-tool mapping work; fails closed on upstream format changes    |
| Signature/attestation verification (`gh attestation verify`) | Rejected for now — publication for these tools' releases is unconfirmed; revisit if checksums are later judged insufficient.      | Depends on tooling and publisher adoption                         |
| Package-manager paths (Homebrew cask, npm)   | Rejected — casks carry no sha256, npm route depends on the fnm bootstrap; adds mid-install ordering hazards with no integrity gain. | New runtime prerequisites in bootstrap order                      |

## Decision Outcome

Chosen option: **Install checksum-verified release artifact**, because it
removes the unverifiable-code-execution surface entirely: nothing remote is
ever parsed as shell, and what lands on disk is byte-identical to the artifact
the publisher's own checksum covers.

Rules that follow:

- Setup scripts install tools from release artifacts verified against the
  publisher's integrity material (checksum mandatory, fail closed on any
  missing or mismatching material); they do not execute remote install
  scripts.
- Verification failure aborts the individual setup step, loudly, and the run
  continues other steps (per-step error semantics unchanged).

### Positive Consequences

- The compromised-script and truncated-download execution paths are gone for
  covered tools; the installed bytes equal the published bytes.
- Fail-closed checks turn upstream format changes into visible errors instead
  of silent unverified installs (strictly better than the best-effort check
  the upstream installers themselves perform).
- One small script, no new runtime prerequisites; reruns stay network-free
  behind the skip guard.

### Negative Consequences

- Residual risk: artifact and checksums originate from the same release
  channel, so a publisher-side compromise of the release-publishing pipeline
  defeats the check; closing it needs signatures/attestations — out of scope
  by the bounded-goal driver.
- Upstream stops or renames publishing checksum material → installs fail
  closed until the contract is updated; that is the intended direction of
  failure, but it is maintenance.
