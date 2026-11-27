# E2E run record collection gate

- Status: accepted
- Deciders: Matias Olivera
- Date: 2026-11-27

## Context and Problem Statement

The e2e verification runs in a temporary VM and records per-step spans, logs and
a summary on the host. When record collection fails, the phase currently only
warns and still succeeds. A run can therefore be reported green while its record
directory is empty or its summary has no spans, leaving nothing to inspect after
the VM is deleted. The earlier decision to keep collection failures non-fatal
was made so a transfer problem could not mask an otherwise passing run; this
issue reverses that trade-off. Live delivery to the local collector remains a
separate, opportunistic path whose failure is explicitly not a gate condition.

This record supersedes `0009-e2e-run-observability` on the point that record
collection failures are non-fatal; its file-first, best-effort live-delivery
decision otherwise stands.

## Decision Drivers

- A green run must leave inspectable, usable evidence of what it did.
- A failure to obtain or interpret that evidence must be loud, never silent.
- An unreachable live collector must not fail the gate: durable records are the
  documented fallback.
- The gate's existing command-status contract must stay intact: a real
  verification failure must not be masked by a secondary collection failure.
- The change must stay local to host-side verification, with hermetic coverage
  and no new dependency on the observability stack.

## Considered Options

| Option | Outcome | Cost |
| --- | --- | --- |
| Warn only (status quo) | Lost: green runs can leave no inspectable records | None |
| Fail on collection failure and empty records; keep live delivery best effort | Won: honest gate with durable evidence, no new service dependency | Small; transient transfer faults now fail a phase |
| Fail on unreachable live collector too | Lost: contradicts the documented fallback and adds a local-service dependency | Small |
| Require every record artifact (metadata and per-span logs) | Lost: broader validation than the issue asks for and brittle for partial phases | Moderate |

## Decision Outcome

Chosen option: **fail the e2e phase when its records cannot be collected or are
empty, while keeping live delivery best effort**.

- A phase passes only when its wrapped verification succeeds and its durable
  records contain at least one step in the summary.
- Collection failures, unusable archives and an empty record set are reported as
  errors and fail the phase; an unreachable live collector is still a warning.
- When both the wrapped verification and collection fail, the verification's
  status is preserved so the primary failure is not hidden by a secondary one.
- The rejected alternatives are warning-only behavior (silently loses
  evidence), gating on the live collector (breaks the documented fallback), and
  strict validation of every record artifact (out of scope).

### Positive Consequences

- A successful run always leaves inspectable records and a step summary.
- Missing evidence is attributed to record collection rather than silently
  ignored, matching the repository's loud-failure principle.
- Live observability remains optional, as documented.

### Negative Consequences

- A transient VM transfer or archive fault now fails an otherwise successful
  phase; rerunning the phase is the mitigation.
- The changed behavior reverses the earlier warning-only expectation recorded
  in past specifications, which remain as historical context.
