# plan.md - `078-speed-up-e2e-verification`

> Technical blueprint. No provisional decisions: every non-trivial choice MUST
> create its decision record inline through the repository's decision-record
> skill.

## Architecture

Four touch points, sequenced so the measurement exists before any optimization:

1. `setup/helpers/observability.sh` — add `observability_phase_begin <label>`
   and `observability_phase_end <status>`. They record a start timestamp even
   before observability is initialized and emit one `kind="phase"` span through
   the existing `observability_span` when enabled. The phase span is standalone:
   step spans keep their current parent, so `steps.sh` is untouched.
2. `setup/install.sh` and `setup/post-install.sh` — begin a phase at the point
   their existing `[+Ns] ... total` timer starts; end it just before
   `report_failed_steps`, with status derived from `FAILED_STEPS`. Non-e2e runs
   emit nothing because the helpers no-op when observability is disabled.
3. `tests/observability/dashboards/e2e-runs.json` — add a `run_id` template
   variable; show the per-run phase total as a sortable table (long run ids make
   a single stretched bar unreadable); add panels for time by call type and
   package-manager time by tool; keep the existing slowest-steps and
   download-by-host bar-gauge styling and sort both by descending duration with
   a reduce → sort-by-value → rows-to-fields transform chain, scoped by run.
   Update in place under the existing uid, keeping live and alert panels
   unchanged.
4. `docs/runbooks/grafana-query-cookbook.md` — add the record-backed queries
   used by the new panels.

A hermetic test (`tests/observability/phase-span-test.sh`) covers emission before
the dashboard work; the static gate covers the rest.

## Data models

New span kind `phase` in `spans.jsonl`, using the existing span shape: `name` is
`install.sh` or `post-install.sh`, `kind` is `phase`, `phase` is the e2e phase,
`run_id`, `duration_ms`, `status` and `exit_code` follow current conventions.
No migration: `tests/e2e-observability.sh` filters `kind=="step"` for its
summary, so phase spans are invisible there. Download child spans also carry a
top-level `url_host` field, copied from their attributes array, so LogQL can
group by host.

## API contracts

| Acceptance scenario | Contract |
| --- | --- |
| a run's total install time is visible | phase span from `install.sh`; dashboard panel "Install total by run (records)"; cookbook row "total install time per run" |
| each phase emits a root span | `observability_phase_begin`/`observability_phase_end` in both setup scripts; one phase span per run and phase |
| slowest steps are ranked descending | existing "Slowest steps" bar gauge keeps its styling and is sorted by descending duration with a transform chain, scoped by the `run_id` variable |
| the dominant cost is attributed | panels "Time by call type", "Package-manager time by tool", "Download time by host", using `attributes_kind`, `attributes_name`, `attributes_url_host` |
| queries are reproducible | cookbook rows mirroring each record-backed panel query |
| normal setup is unaffected | helpers gated on `observability_enabled` |
| static gate stays green | `./tests/test.sh` (no `--vm`) and the new hermetic test |

## Decisions

- `docs/decisions/0013-e2e-speedup-sequencing.md` — measure before optimizing;
  extend the existing views rather than creating a second workflow.

## Risks

- Every timing panel must filter `attributes_kind`; otherwise phase spans double
  count step and child spans. Verification: panel queries reviewed against the
  recorded spans and the cookbook states the rule.
- Replayed records share an ingest timestamp. Bounded windows and `run_id`
  grouping keep runs separate; verification after starting the stack.
- With `FAIL_FAST=1` a failed step exits before `observability_phase_end`, leaving
  no phase span. E2e does not set `FAIL_FAST`; documented as a known limit.
- A `run_id` variable fed by Loki structured metadata is empty until records are
  replayed; `includeAll` keeps panels usable before the first replay.
- Reverting is local: remove the two helper calls and the new panels; the span
  format change is additive and does not invalidate existing records.

## Assumptions

- `| json` on replayed spans exposes `attributes_kind`, `attributes_run_id`,
  `attributes_phase`, `attributes_name`, `attributes_duration_ms` and
  `attributes_url_host`. Source: collector config, existing dashboard queries.
  Verification: confirm the new queries return rows in Explore after replay.
- A `kind="phase"` span is ignored by the summary filter on `kind=="step"`.
  Source: `tests/e2e-observability.sh`. Verification: check `summary.tsv` after a
  phase run.
