# Release automation and changelog

- Status: accepted
- Deciders: Matias Olivera
- Date: 2026-11-25

This record supersedes `0004-release-notes-grouping` on two points: an external
generator is no longer rejected outright, and the generated notes are no longer
the repository's only changelog. ADR 0004 remains authoritative for the
grouping rules and the label convention.

## Context and Problem Statement

Releases are cut by following prose steps by hand. An agent that follows that
prose spends its context on a fixed sequence, and the text can drift from what
publishing actually requires. The generated-notes rule is the easiest part to
get wrong: notes resolve their grouping configuration at the release target,
so a configuration change that has not been promoted has no effect on the
release. A previous issue documented the rule, but the knowledge still lives
outside the mechanism.

## Decision Drivers

- A fixed release sequence belongs in code, not in prose or in a judgment-heavy
  skill that an agent must re-derive each time.
- The human promotion of the integration branch is the meaningful review point
  and must remain the only approval for publication.
- The release page must keep the label-driven grouping that was deliberately
  chosen for this repository, and must resolve it at the release target.
- An exhaustive, generated history needs one authoritative home that cannot
  drift from the notes shown on the release page.
- Release tooling must be pinned and integrity-checked in local use and in
  automation, and failures must stop loudly rather than publish partially.
- Verification must be hermetic: tests cannot depend on a live repository,
  network or credentials.

## Considered Options

| Option | Outcome | Cost |
| --- | --- | --- |
| Automate the sequence, keep GitHub-generated notes at the target, add a generated exhaustive changelog | Won: preserves the chosen grouping and gives the history a stable home without a second notes taxonomy | One pinned tool plus a small automation surface |
| Automate the sequence and generate the release body from commit history | Lost: commits carry no pull-request labels, so it cannot reproduce the chosen grouping and creates a second configuration that drifts | Another template to maintain; grouping semantics lost |
| Keep the procedure as prose or a project skill | Lost: an agent re-derives a fixed checklist every release and the text drifts from the mechanism | No setup, recurring human cost |
| Adopt a release bot that opens its own release pull request | Lost: adds a second gate or removes the human promotion gate | Extra automation and review surface |
| Keep manual steps with rules documented in the tracker | Lost: the target-branch rule keeps being rediscovered | Ongoing manual verification |

## Decision Outcome

Chosen option: **automate the release sequence, keep GitHub-generated notes at
the release target, and add a generated exhaustive changelog**, because it puts
the fixed sequence in code while preserving the grouping this repository
already decided on.

- The promotion merge is the sole approval. Nothing creates a tag or release
  before it; publication follows from the merge itself.
- The version and the exhaustive changelog come from commit history through a
  pinned, integrity-checked tool. The changelog is generated output, never
  hand-edited, and regeneration on a clean tree is diff-free.
- The release body remains generated at the release target by the platform,
  using the label-driven grouping already chosen for this repository. It is
  shown before publication through a read-only preview and published as shown.
- Tags are anchored to the promotion merge and reachable from the integration
  branch, so released work is never counted twice in the next changelog.
- A partially failed publication is resumable, but a tag at a different commit
  is never moved or overwritten.

### Positive Consequences

- The release sequence is one mechanical entry point instead of prose an agent
  must reconstruct.
- The reviewable promotion is the only human gate, and publication cannot race
  ahead of it.
- The exhaustive history and the grouped release page have separate, stable
  sources that cannot silently contradict each other.
- The target-branch rule is enforced by the mechanism rather than rediscovered.
- Tooling is accountable locally and in automation, and tests stay hermetic.

### Negative Consequences

- Release notes still depend on labels being present at merge time; the
  residual grouping rule from ADR 0004 keeps a missing label visible.
- Preview and publication are separate moments, so a label change between them
  can alter the notes; publishing shows the final notes immediately before
  creating the release.
- A pinned external tool adds a download and checksum step to every release
  environment.
- Merge-back changes the integration branch after a promotion, so a conflict
  there stops publication and needs a human resolution.
