# Antigravity CLI Artifact Integrity Source

- Status: accepted
- Deciders: Matias Olivera
- Date: 2026-11-19

## Context and Problem Statement

The Antigravity CLI's documented installer executes a remote script without
integrity verification. Google publishes platform manifests for its CLI
artifacts; the Linux x64 and ARM64 manifests observed on 2026-11-19 include
artifact URLs and SHA-512 digests. GitHub also exposes release-asset SHA-256
digests. Which integrity source should setup trust, and what should happen when
the maintainer's manifest cannot be used?

## Decision Drivers

- Setup must not execute remote code it cannot verify (ADR 0003).
- Integrity material published by the software maintainer is the preferred
  source.
- A GitHub-computed digest is an acceptable fallback only when the maintainer
  publishes no usable integrity material for the artifact.
- An unavailable or malformed publisher manifest must fail closed; it does not
  establish that publisher integrity material is absent.
- Verification must complete before the artifact is installed.

## Considered Options

| Option | Outcome | Cost |
| --- | --- | --- |
| Execute Google's installer script | Rejected — executes remote code without verifying the script. | Minimal change, violates ADR 0003. |
| Prefer Google's checksum and use GitHub's digest only when Google publishes none | **Chosen** — uses the maintainer's integrity statement first and retains a verifiable fallback. | Requires handling two metadata formats and sources. |
| Use GitHub's digest unconditionally | Rejected — ignores the more direct integrity material Google publishes. | Simpler lookup, weaker source preference. |
| Pin a self-authored checksum | Rejected — the hash would be self-recorded and require a manual re-audit for each release. | Per-release maintenance and TOFU risk. |

## Decision Outcome

Chosen option: **Prefer maintainer-published integrity material, with a
GitHub-digest fallback only when that material is absent**, because it follows
the publisher-first rule while retaining a verifiable path when the publisher
does not provide integrity data.

If the publisher manifest is unreachable or malformed, setup fails closed
without trying a weaker source. When a valid publisher response contains no
usable checksum or signature, GitHub's release asset digest may be used for the
matching version and artifact. If neither source provides integrity material,
installation fails closed.

### Positive Consequences

- The artifact is verified against Google's own published SHA-512 when
  available.
- GitHub's computed digest remains available for releases where the maintainer
  publishes no checksum or signature.
- Network and parsing failures cannot silently downgrade the verification
  source.

### Negative Consequences

- The fallback path depends on both a matching GitHub release and its asset
  digest being available.
- Supporting distinct publisher and GitHub metadata sources adds parsing and
  failure cases to the installer.
