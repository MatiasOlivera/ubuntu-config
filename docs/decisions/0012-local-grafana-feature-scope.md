# Local Grafana feature scope

- Status: accepted
- Deciders: Matias Olivera
- Date: 2026-11-24

## Context and Problem Statement

The local observability stack collects per-step spans, logs and metrics from
end-to-end verification runs. Those signals need a stable set of Grafana
capabilities that turns them into ready-made views and locally evaluated
failure signals. Without a stated scope, later observability work can drift
into overlapping or heavyweight features, or assume delivery and team
workflows this repository does not have. This decision records which
capabilities the repository relies on and which it deliberately leaves out.

## Decision Drivers

- Run inspection must work from the durable records whether or not the stack
  was running while the run happened.
- Failure signals must be definable and evaluable locally, without an external
  delivery target.
- The verification gate must not depend on Grafana or any local service.
- The repository is personal, single-user and local-only; capabilities aimed
  at teams or continuously served production systems add cost without benefit.
- Configuration lives in the repository and is reviewed like code, so simple
  declarative capabilities are preferred over UI-managed or hosted state.

## Considered Options

| Option | Outcome | Cost |
| --- | --- | --- |
| Ready-made views and local failure rules, no delivery | Won: covers inspection and evaluation with no operational target | Small set of declarative definitions |
| Datasource-only with ad-hoc queries | Lost: every inspection starts from an empty query, and collected signals go unused | None |
| Full operational Grafana feature set | Lost: SLOs, on-call, notifications and reporting assume a served service and a team | High configuration and maintenance cost |
| Hosted monitoring service | Lost: conflicts with the local-only, self-contained verification workflow | External dependency and account management |

## Decision Outcome

Chosen option: **ready-made views and local failure rules without delivery**,
because it puts the collected signals to work while keeping the stack entirely
local and independent of the test gate.

- A ready-made view of an end-to-end run is part of the stack, built on both the
  replayed records and the live trace-derived metrics. Ad-hoc exploration
  remains available alongside it.
- Failure rules are defined and evaluated against the local datasources for
  inspection only. There are no contact points, delivery routes, schedules or
  external sinks.
- The existing datasource-level correlation between traces, logs and metrics
  stays the integration model; no parallel workflow is introduced.
- Capabilities that assume a continuously served service, a team, or a delivery
  target are out of scope: objectives and error budgets, on-call and incident
  routing, reporting, snapshots, synthetic monitoring, machine learning and
  anomaly detection, annotations, layered access control, plugins, and hosted
  or API-managed configuration.
- Stack startup remains a documented manual step outside the verification gate.

### Positive Consequences

- Opening the stack after a run shows per-app step spans and timing immediately.
- Failures are evaluable and visible locally without configuring a recipient.
- The scope is short enough to state and to keep stable as the stack evolves.
- The verification gate remains independent of Grafana and host services.

### Negative Consequences

- No notification means a rule state is only seen when Grafana is opened.
- Trace-derived metrics only exist when the stack runs during a run, so the
  record-replay views carry inspection in the common "start afterwards" case.
- The chosen scope must be revisited if this repository ever adopts a hosted
  instance or shared on-call workflow.
