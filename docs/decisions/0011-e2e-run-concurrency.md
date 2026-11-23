# End-to-end run concurrency control

- Status: accepted
- Deciders: Matias Olivera
- Date: 2026-11-23

## Context and Problem Statement

The end-to-end verification run uses one VM per checkout. Two runs started
against the same checkout install into that VM at the same time, contend for the
package manager's lock, and fail after long timeouts with messages that suggest
genuine install failures. Per-worktree VM isolation does not cover two runs on
one worktree. The problem is local-host verification only; CI runners are out of
scope.

## Decision Drivers

- At most one active run may use a VM, so a run's result reflects only its own work.
- A contender must learn about the conflict immediately and explicitly, not after
  a long install attempt.
- Independent worktrees must remain independently verifiable.
- Ownership must end when a run ends, including abnormal termination, without a
  manual cleanup ritual.
- The guard must be verifiable hermetically and must not add a host service,
  network dependency, or new package requirement.
- If enforcement is unavailable, the run must fail closed rather than proceed
  unguarded.

## Considered Options

| Option | Outcome | Cost |
| --- | --- | --- |
| Fail fast with one active run per VM | Won: immediate, attributable failure with no overlapping installs | Small helper and hermetic test; needs a host-owned lock primitive |
| Blocking per-VM ownership (wait for the first run) | Lost: long opaque wait with no signal about which run will go next | Low |
| Opt-in wait mode alongside fail-fast | Lost: extra flag, docs and test surface for a case nobody asked for | Moderate |
| One lock for all end-to-end runs | Lost: blocks unrelated worktrees that have their own VMs | Low |
| Infer activity from VM state before starting | Lost: races and cannot distinguish a kept idle VM from one in use | Low but unreliable |
| Document the caution without enforcing it | Lost: same misleading failures remain | None |

## Decision Outcome

Chosen option: **fail fast with one active run per VM**, because the second run
cannot produce a trustworthy result anyway, so rejecting it immediately is both
the cheapest and the least surprising behavior.

- Ownership is scoped per VM, not per host; runs against different worktrees
  proceed in parallel.
- A contender is rejected before doing any verification work, with an error that
  names the affected VM.
- Ownership is held by the run process and released by the operating system when
  that process ends, including abnormal termination; no manual cleanup exists.
- A run that cannot establish ownership fails closed with a clear message.
- The guarantee concerns only local end-to-end runs; no queueing, transaction or
  rollback semantics are introduced for the VM state itself.

### Positive Consequences

- Package-manager lock contention and its spurious failures cannot occur.
- Every reported result belongs to exactly one run.
- A conflict is visible in one line before time is spent on verification.
- A crashed run leaves no stale guard state to clean up.

### Negative Consequences

- The user must wait for the active run to finish before retrying.
- The guard depends on a host-level lock primitive; a host without it cannot run
  the end-to-end check, by design.
- One small helper and its test join the test suite's maintenance surface.
