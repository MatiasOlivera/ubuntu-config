# End-to-end run observability

- Status: accepted
- Deciders: Matias Olivera
- Date: 2026-11-23

## Context and Problem Statement

The end-to-end verification run launches a Multipass VM and is local-only. When
it fails, it reports only aggregate phase timings: no per-app duration or
outcome, no way to read one app's logs afterwards, and no record to compare
with a previous run. A later performance pass therefore cannot tell whether
time went to downloads, installation, or VM setup.

Today the only log capture is a helper that stores one whole-run log file on the
host. Keeping it beside a richer system would leave two competing logging
workflows. The new records must also be stored on the host so they survive VM
deletion and remain available for later analysis.

## Decision Drivers

- Failures must be attributable to an app and diagnosable from its own logs.
- Download and install costs must be distinguishable to guide optimization.
- Records must survive VM teardown and remain analyzable long after a run.
- The test gate must not depend on a local service or host networking.
- Instrumentation must not distort the timings it measures.
- The repository is personal, single-user and local-only; operational heaviness
  is acceptable only when it buys analysis capability.
- There must be one logging workflow, not two.

## Considered Options

| Option | Outcome | Cost |
| --- | --- | --- |
| Aggregate phase timings only | Lost: no per-app attribution or comparison | None |
| Parse the existing console markers | Lost: no spans, log correlation or metrics | Small, but fragile |
| Instrument the step runner without a stack | Lost: no UI or cross-run analysis | Small |
| Full local observability stack, live delivery only | Lost: data lost on abrupt failure; depends on host reachability | Moderate |
| Full local observability stack, file-first with best-effort live delivery | Won: durable source of truth plus live views | Heavier local stack and two emit paths |
| Broad host and resource telemetry | Lost: no actionable signal for a fixed VM configuration | Extra collection and privacy cost |

## Decision Outcome

Chosen option: **a file-first local observability stack with best-effort live
delivery**, because it preserves every record regardless of service or network
availability while still providing trace waterfalls, log correlation and
cross-run metrics when the stack is running.

- Durable per-run records are authoritative; live delivery is opportunistic and
  must never change a run's outcome.
- Traces are the primary model: one span per install or config step, with child
  spans for downloads and package-manager calls, and network/disk byte counters.
- Logs belong to their step's span so a failure can be diagnosed from the trace.
- Metrics retain per-app duration and outcome across runs.
- Disk footprints are approximate, derived from declared install paths and the
  package database; full filesystem snapshots are limited to once per run
  because they are slow enough to distort step timings.
- Only run and environment identifiers are recorded. Host details and CPU/RSS
  accounting are out of scope.
- The legacy whole-run log helper is removed; the stack is the single logging
  workflow. Stack startup is a documented manual step, not part of the test
  gate.

### Positive Consequences

- A failed run names the app, shows its logs, and leaves inspectable records.
- Download versus install cost is visible for choosing optimizations.
- Runs can be compared by query or dashboard weeks later.
- Instrumentation cannot break the verification gate when the stack is down.

### Negative Consequences

- A local multi-service stack costs setup time and machine resources.
- Two emission paths must carry consistent identifiers.
- The declared-path disk accounting needs maintenance as installers change;
  a drift check mitigates stale entries.
- Download inside package-manager commands remains bundled and cannot be split
  without deeper tracing.
