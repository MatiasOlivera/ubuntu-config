# plan.md - `078-speed-up-e2e-verification`

## Architecture

Two phases, in sequencing order.

**Phase 1 — measurement (shipped).**

1. `setup/helpers/observability.sh` — `observability_phase_begin <label>` and
   `observability_phase_end <status>` emit one `kind="phase"` span per setup
   phase without touching `steps.sh`.
2. `setup/install.sh` and `setup/post-install.sh` — begin/end the phase at their
   existing total timers; non-e2e runs emit nothing.
3. `tests/observability/dashboards/e2e-runs.json` — `run_id` variable, per-run
   total as a table, call-type and package-manager-tool panels, slowest-steps
   and download-host gauges sorted descending via a transform chain.
4. `tests/observability/phase-span-test.sh` and `tests/observability/shims-test.sh`
   cover phase emission and the queryable `url_host` field; the cookbook carries
   the queries.

**Phase 2 — repeat-run overhead (this plan).**

1. Benchmarks first, already run: a warm-VM `--reuse` run (105 s total vs 20 s +
   2 s of scripts), bare exec (~0.2 s), wrapper with record copy (~2 s), an
   orphaned-sleep reproduction, transfer vs `classic`/`native` mounts, and a
   fresh install at 4 CPU / 8 G. Results are in the spec context and ADR 0014.
2. Change the two sudo keepalive loops in `setup/install.sh` and
   `setup/post-install.sh` so their output streams are fully redirected. No
   harness restructuring: the measured per-call cost is too small to justify it.
3. Keep the single repo transfer and the record-copy step; the mount comparison
   showed sub-second data movement in both directions and no usable `native`
   mount on a running VM.
4. Keep the VM defaults at 2 CPU / 4 G / 50 G; the one larger-allocation sample
   is not enough to justify a change.
5. Add a hermetic regression test that fails if either keepalive loop regains an
   inherited output stream, using a small reproduced pipe scenario and a
   contract check on both entry scripts.
6. Phase 3: make the version checks for `opencode` and `openusage` look in their
   per-user install directories, with tests asserting the skip guard and the
   versions report. This also corrects two false MISSING entries.
7. Phase 3: add a dev-only helper under `tests/` that takes the current checkout
   state against a recorded seed, re-copies the repo into the kept VM, runs
   `apt update`, and executes only the changed setup scripts' dispatchers. It
   accepts a stubbed Multipass command for hermetic testing and never changes
   what `./tests/test.sh --vm` verifies.

## Data models

Phase-1 span schema stays as shipped: `kind="phase"` spans carry `name`, `phase`,
`run_id`, `duration_ms`, `status` and `exit_code`; download child spans carry a
top-level `url_host`. Phase 2 changes no persisted format.

## API contracts

| Acceptance scenario | Contract |
| --- | --- |
| a run's total install time is visible | phase span from `install.sh`; dashboard table "Install total by run (records)" |
| each phase emits a root span | `observability_phase_begin`/`observability_phase_end` in both setup scripts |
| slowest steps are ranked descending | "Slowest steps" bar gauge with the sort transform chain |
| the dominant cost is attributed | call-type, package-manager-tool and download-host panels |
| queries are reproducible | cookbook rows mirroring the panel queries |
| a phase command returns when its script finishes | redirected keepalive streams in both setup scripts; regression test asserts it |
| a failed phase still fails the run | existing `FAILED_STEPS`/`report_failed_steps` behaviour unchanged |
| records are copied once even on failure | existing `e2e-observability.sh` copy path unchanged |
| fresh runs are unchanged | plain `--vm` branch in `tests/test.sh` unchanged |
| mount and transfer are compared | recorded benchmarks for tarball, `classic` and (where possible) `native` mounts |
| resource sizes are compared | recorded benchmarks at 2 CPU / 4 G and 4 CPU / 8 G |
| the repeat speedup is measured | before/after wall-clock numbers for the same warm-VM scenario |
| static gate stays green | `./tests/test.sh` (no `--vm`) and the new hermetic test |

## Decisions

- `docs/decisions/0013-e2e-speedup-sequencing.md` — measure before optimizing;
  extend the existing views rather than creating a second workflow.
- `docs/decisions/0014-repeat-run-round-trips.md` — fix stream ownership of the
  keepalive loops; reject a harness rewrite, persistent mounts, package caches
  and unproven resource changes.

## Risks

- Every timing panel must filter `attributes_kind`; otherwise phase spans double
  count step and child spans.
- Replayed records share an ingest timestamp; bounded windows and `run_id`
  grouping keep runs separate.
- With `FAIL_FAST=1` a failed step exits before `observability_phase_end`, leaving
  no phase span. E2e does not set `FAIL_FAST`; documented as a known limit.
- A `run_id` variable from Loki structured metadata is empty until records are
  replayed; `includeAll` keeps panels usable before the first replay.
- Redirecting the keepalive's streams does not kill the orphaned `sleep`; it only
  stops holding the caller's pipe open. The sleep exits on its own within its
  interval, and the loop notices its parent is gone.
- The sizing comparison is one sample per allocation; it is recorded as a data
  point, not a basis for changing defaults.
- Reverting is local: restore the two stream redirections. No harness or VM
  state change is involved.

## Assumptions

- `multipass exec` waits for EOF on its output streams. Source: the orphaned
  sleep reproduction. Verification: before/after warm-run timings.
- The two setup entry scripts are the only sources of an inherited background
  stream in the phase commands. Source: the in-VM patch that removed the gap.
  Verification: a real `--reuse` run after applying the fix in the repository.
- Transfer and mount data movement are both sub-second. Source: the benchmark.
  Verification: recorded numbers in the decision record.
