# Artifact integrity source priority

- Status: accepted
- Deciders: Matias Olivera
- Date: 2026-11-20

## Context and Problem Statement

Release artifacts may have integrity material published by the software
maintainer and a SHA-256 digest computed by GitHub. These sources make different
claims about the bytes. Setup needs a consistent rule for choosing between
them, and must remain fail-closed when neither provides usable verification.

## Decision Drivers

- Prefer integrity statements controlled by the software maintainer.
- Preserve a verifiable install path when the maintainer publishes no usable
  material.
- Never accept unverified artifacts or treat a self-recorded hash as
  independent evidence.
- Keep existing accepted integrity decisions valid unless explicitly
  superseded.

## Considered Options

| Option | Outcome | Cost |
| --- | --- | --- |
| Require maintainer-published integrity material only | Rejected — safe but blocks artifacts when maintainers publish no usable material despite an available GitHub digest. | Some otherwise verifiable installs become unavailable. |
| Prefer maintainer material, then use GitHub's release asset SHA-256 digest | **Chosen** — follows the more direct maintainer statement while retaining an independent check of the bytes uploaded to GitHub as a fallback. | The two sources must be distinguished and fallback use explained. |
| Accept either source without priority | Rejected — leaves source selection inconsistent and does not express the preference for maintainer-controlled material. | Reviewers cannot apply one predictable rule. |

## Decision Outcome

Chosen option: **Prefer maintainer-published integrity material, with GitHub's
release asset SHA-256 digest as fallback**, because it prioritizes the
maintainer's statement while keeping a verifiable path when that statement is
unavailable.

For each artifact, inspect the maintainer's official distribution channels
first. Use usable maintainer-published checksums or signatures when available;
otherwise use GitHub's release asset SHA-256 digest when available. If neither
source provides usable material, fail closed and require an explicit exception
decision. Never substitute a self-authored hash pin. Existing accepted
integrity decisions remain valid unless a later decision explicitly supersedes
them.

### Positive Consequences

- Source selection is predictable and gives priority to the maintainer's own
  integrity statement.
- GitHub's digest can verify uploaded release bytes when the maintainer
  publishes no usable material.
- The fail-closed rule prevents silent acceptance when both sources are
  unavailable.

### Negative Consequences

- A GitHub-computed digest confirms the bytes GitHub hosts, not the
  maintainer's intent; compromise before upload can affect both the artifact
  and that digest.
- Maintainer channel checks add review work, and fallback use needs a recorded
  reason.
