# spec.md - `030-surface-failed-install-steps`

## Context

Issue: [#30](https://github.com/MatiasOlivera/ubuntu-config/issues/30), milestone
`v0.4.0 - reliability: honest verification`.

`setup/install.sh` and `setup/post-install.sh` time each `install_*`/`config_*`
step through a wrapper that already captures the step's return status. The
top-level calls ignore that status and a final timing `printf` leaves each
script exiting 0. A broken install is therefore reported as success; the only
hint is an advisory MISSING row in `reports/versions.sh`.

This conflicts with constitution axioms 2 and 3 (least surprise — failures stop
loudly; trust — loud failure, never silent partial action) and the milestone's
"honest verification" goal: the run's exit status must reflect its steps.
The existing non-interactive contract still stands: `config_sync_credentials`
reports pending secrets and returns 0 with no tty, so an unattended run is
never blocked by missing secrets.

Design decisions settled with the issue owner:

- Accumulate failed steps, report them, then exit nonzero at the end — do not
  fail fast by default. Every step still runs, so one broken app does not hide
  the rest of the machine's state or stop later steps.
- Both `install.sh` and `post-install.sh` are in scope; they share one step
  runner.
- Opt-in `FAIL_FAST=1` stops at the first failing step for callers that prefer
  immediate termination.
- Credential sync stays advisory and outside the failed-step count, so the
  count describes failed install steps only.
- Rejected: `set -e` / default fail-fast (breaks per-step status capture and
  hides later failures); opt-in-only strict mode (leaves the default silent
  success bug unfixed).

## User stories

- As a person running setup, I want a failed step to make the run exit
  nonzero, so I stop believing a broken machine was configured successfully.
- As a person running setup, I want all steps attempted and one summary naming
  every failure, so a single failure does not mask the others or prevent the
  rest of the machine from being configured.
- As an automated caller (CI or the e2e gate), I want the script's exit status
  to reflect step failures, so a broken install fails the gate.
- As a person who prefers immediate termination, I want an opt-in switch, so I
  can stop at the first failure without changing the default for everyone.
- As a person running unattended setup, I want missing secrets to remain an
  advisory pending report, so credential sync neither blocks the run nor
  inflates the failed-step count.

## Acceptance criteria (BDD)

```gherkin
Scenario: a clean run reports success
  Given every install and config step succeeds
  When setup/install.sh (or setup/post-install.sh) finishes
  Then each step still prints its wall-clock timing line
  And the script prints its total timing line
  And the script exits 0

Scenario: failed steps are accumulated and reported
  Given two steps return nonzero and all other steps succeed
  When setup/install.sh (or setup/post-install.sh) finishes
  Then every step, including those after the failures, was attempted
  And each failing step is named with its nonzero status as it happens
  And a final summary names both failed steps and their count
  And the script exits 1

Scenario: opt-in fail-fast stops at the first failure
  Given FAIL_FAST=1 is set and a step returns nonzero
  When setup/install.sh (or setup/post-install.sh) runs
  Then the failing step is named with its nonzero status
  And no later step is attempted
  And the script exits with that step's nonzero status

Scenario: credential sync stays advisory
  Given config_sync_credentials returns nonzero in an interactive run
  When setup runs
  Then its timing line still appears
  And it is not named in the failed-step summary
  And it does not by itself make the run exit nonzero or trigger fail-fast
  And in a non-interactive run it still reports pending secrets and returns 0

Scenario: reruns remain safe
  Given a previous run already installed everything
  When setup runs again with no failing steps
  Then the version report and total timing line still print
  And the script exits 0
```

## Constraints

- [ ] Both `setup/install.sh` and `setup/post-install.sh` use the same step
      runner; no step is dropped or reordered in the run.
- [ ] Default behavior keeps running all steps; `FAIL_FAST=1` is the only
      fail-fast switch, and it is documented in `README.md`.
- [ ] `config_sync_credentials` keeps its non-interactive behavior (reports
      pending, returns 0) and is never counted as a failed install step.
- [ ] The shared runner is source-only (no side effects on `source`) and stays
      shellcheck-clean so `tests/test.sh` phases 2-5 stay green.
- [ ] No change to dispatchers, `reports/versions.sh`, per-app scripts, or the
      sudo keepalive / EXIT trap.
- [ ] The functional test is hermetic per `tests/AGENTS.md`: no real sudo,
      network, keyring, or system changes — stubs only.
