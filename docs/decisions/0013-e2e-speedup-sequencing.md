# Sequencing of end-to-end speedup work

- Status: accepted
- Deciders: Matias Olivera
- Date: 2026-11-24

## Context and Problem Statement

End-to-end verification takes tens of minutes and is repeated often, but the
harness originally reported only aggregate phase timings. Issue #78 asks for a
data-driven optimization pass rather than a prescribed fix, and waits on the
per-app observability work. That work now records per-step spans, download and
package-manager child spans, and summaries that survive VM teardown. However,
there is no reliable per-run total, no full descending ranking of slow steps,
and no split of time by call type or host, so an optimization chosen today would
rest on a few single-run samples. The choice is whether to optimize now from
those samples or to make the measurements durable and comparable first.

## Decision Drivers

- Optimizing the wrong component is more expensive than measuring first.
- Single-run samples vary widely, so before/after claims need comparable records.
- Repository guidance makes non-trivial decisions durable artifacts.
- The verification gate must stay offline and depend on no running service.
- Records must remain useful after the VM is deleted.
- There must be one observability workflow, not a competing one.

## Considered Options

| Option | Outcome | Cost |
| --- | --- | --- |
| Optimize from existing step timings | Lost: the slowest step varies per run, so the target is not established | None |
| Build a separate timing dashboard | Lost: a second workflow competes with the existing observability views | Moderate |
| Extend the existing views with per-phase totals and a call-type split, then decide | Won: comparable per-run numbers and a traceable target before any code change | Small |
| Skip measurement and ship a cache | Lost: no baseline and no way to tell whether upstream freshness is still detected | Moderate |

## Decision Outcome

Chosen option: **extend the existing end-to-end observability views with
per-phase totals and a call-type split, then choose the optimization from those
measurements**, because the issue's acceptance criteria require a measured
bottleneck and before/after timings that a few single-run step timings cannot
support.

- Each verification phase has a single authoritative total, independent of how
  many steps that phase happens to run.
- Existing per-step and child-span records stay the source of attribution; the
  new totals supplement rather than replace them.
- The optimization decision and its freshness trade-offs are recorded only after
  the measurement pass produces comparable runs.

### Positive Consequences

- Runs can be compared by total and ranked by dominant cost.
- Before/after claims cite records rather than single console samples.
- The chosen optimization is traceable to evidence in the decision archive.

### Negative Consequences

- The speedup itself is delayed by one measurement pass.
- A new span kind must stay excluded from the existing per-step summary.
- Replayed records share an ingest timestamp, so dashboard ranges need care.
