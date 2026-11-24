# spec.md - `078-speed-up-e2e-verification`

## Context

Issue: [#78](https://github.com/MatiasOlivera/ubuntu-config/issues/78). Reduce the
wall-clock time of the Multipass end-to-end verification run, choosing where to
optimize from measured data rather than guesswork. The issue is blocked by #77's
observability work, which is now available: per-app spans, logs and summaries are
written per run and replayed into a local Grafana stack.

Review of three fresh-run records already sharpens the issue's open question:

| Run | `install.sh` | apt / apt-get | direct downloads | flatpak + snap |
| --- | --- | --- | --- | --- |
| A | 822s | **544s (66%)** | 133s | 99s |
| B | 2451s | **2171s (89%)** | 136s | 102s |
| C | 767s | **300s (39%)** | 285s | 135s |

apt calls — not release downloads and not VM setup — dominate. But these are
three samples, and the dashboard cannot yet show a per-run total, a full
descending ranking of slow steps, or a download-versus-package-manager split.
Before choosing an optimization (and before claiming before/after timings) those
measurements must be durable and comparable across runs.

This spec covers that **measurement pass**, the first phase of #78. The
optimization itself is deliberately deferred: it gets its own decision record
once these numbers, including before/after runs, exist.

## User stories

- As the maintainer, I want each run's total install time shown in Grafana, so I
  can tell whether a change made verification faster instead of guessing.
- As the maintainer, I want the slowest steps ranked in descending order, so I
  can pick the optimization target from data.
- As the maintainer, I want time split into downloads and package-manager calls
  with tool and host names, so I know which repository or release host actually
  dominates.
- As the maintainer, I want to filter panels by run, so one run's numbers are not
  mixed with another's and before/after runs can be compared.
- As the maintainer, I want each phase's total recorded as its own span, so the
  dashboard does not silently miscount when the set of steps changes.
- As the maintainer, I want the queries in the cookbook, so I can reproduce any
  panel in Explore.
- As the test-gate maintainer, I want the static gate green without Grafana,
  Multipass, sudo, or network access, so measurement tooling never weakens the
  check.

## Acceptance criteria (BDD)

```gherkin
Scenario: a run's total install time is visible
  Given two completed e2e runs whose records are replayed into the local stack
  When I open the E2E runs dashboard
  Then a panel shows one value per run id equal to that run's install phase duration
  And each phase duration comes from a single phase-span record, not a sum of step and child spans

Scenario: each phase emits a root span
  Given an e2e install phase and an e2e post-install phase with observability enabled
  When each phase finishes
  Then the run's span records contain exactly one span covering that whole phase
  And each duration matches the harness's reported "install.sh total" or "post-install.sh total"
  And they are labelled as phases rather than steps, so the per-step summary is unchanged

Scenario: slowest steps are ranked descending
  Given recorded spans from several runs with different slow steps
  When I open the E2E runs dashboard
  Then I can see more than five steps ordered by descending duration
  And I can scope that ranking to one run id

Scenario: the dominant cost is attributed
  Given a run whose spans include download and package-manager child spans
  When I open the E2E runs dashboard
  Then panels show total time split by span kind
  And package-manager time is split by tool (apt, apt-get, flatpak, snap)
  And download time is split by host

Scenario: queries are reproducible
  Given a new dashboard panel
  When I follow its query in the Grafana query cookbook
  Then Explore returns the same numbers the panel shows

Scenario: normal setup is unaffected
  Given a normal setup run without an observability record directory
  When install.sh runs
  Then no spans are emitted and its output is unchanged

Scenario: static gate stays green
  Given the full change is applied
  When ./tests/test.sh is run without --vm
  Then all existing checks pass without a running stack, Multipass, sudo, or network access
```

## Constraints

- [ ] Scope is the existing provisioned dashboard, the observability helper,
      `install.sh` and `post-install.sh`, the Grafana query cookbook, and
      hermetic test coverage for the new emission. No other `setup/` install
      script changes.
- [ ] Update the dashboard in place under its existing uid; do not add a second
      competing dashboard or a new datasource.
- [ ] Record-backed panels must keep working when the stack starts after the run
      (replayed file records); live panels and alert rules are untouched.
- [ ] Existing `[+Ns]` console markers and the per-step `summary.tsv` format stay
      unchanged; a phase span must not be reported as a step.
- [ ] No new dependency, no secrets, no host details; the static gate remains
      zero-dependency and offline.
- [ ] Out of scope: choosing or implementing the cache or any other install
      speedup, changing the child-span shims, CI workflows, VM/harness overhead,
      and the observability stack's services.

## Assumptions

- Replayed spans reach Loki through `filelog/spans` + `json_parser` and `| json`
  exposes `attributes_kind`, `attributes_run_id`, `attributes_phase`,
  `attributes_name`, `attributes_duration_ms` and `attributes_url_host`.
  Source: `tests/observability/collector-config.yml` and the existing dashboard
  and cookbook queries. Verification: start the stack and confirm the new
  queries return rows in Explore.
- Replayed records share an ingest timestamp, so their query ranges need a
  bounded window; existing panels use `[5m]`. Source: the dashboard JSON and the
  cookbook's replay caveat. Verification: confirm panels show data after replay.
- A span with `kind="phase"` is ignored by `e2e-observability.sh`'s summary,
  which filters on `kind=="step"`. Source: `tests/e2e-observability.sh`.
  Verification: run a phase and check `summary.tsv` has no phase row.
- Sum of install step durations equals the harness's `install.sh total` within
  the gaps between steps. Source: local records in
  `~/.local/share/ubuntu-config/observability/`. Verification: compare the new
  phase span with the console marker on the next e2e run.
