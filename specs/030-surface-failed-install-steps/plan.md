# plan.md - `030-surface-failed-install-steps`

## Architecture

Two entry points share one source-only runner; no other component changes.

```
setup/helpers/steps.sh (new, shared)
  ├─ step(label, cmd...)         time → run → capture status → print timing
  │                                ├─ success → return 0
  │                                └─ failure → print FAILED(line), record label
  │                                              ├─ default   → return status (keep going)
  │                                              └─ FAIL_FAST=1 → exit with status
  ├─ advisory_step(label, cmd...) same timing, status ignored, never recorded
  └─ report_failed_steps()        print "N step(s) failed: …" → 1 if any, else 0

setup/install.sh
  source runner → unchanged step list → total printf
  config_sync_credentials → advisory_step (advisory, not counted)
  → report_failed_steps || exit 1

setup/post-install.sh
  source runner → unchanged step list → total printf
  → report_failed_steps || exit 1
```

The runner owns process exit only under `FAIL_FAST=1`; the scripts own the final
exit through the report call. Both scripts keep their existing sudo keepalive
and EXIT trap — `exit` passes through the trap without changing the status.

Rejected: inlining the runner in both scripts (duplicated logic, no hermetic
unit test); `set -e` (breaks the per-step `$?` capture and benign nonzero
returns across ~40 library steps); fail-fast by default (hides later failures).

## Data models

`FAILED_STEPS` — a bash array of step labels in run order. Process-local,
fresh on each run, nothing persisted. Labels are the first argument already
passed to `step()` (e.g. `install_uv`), so no new naming scheme is introduced.

## Interface contracts

Runner is source-only: sourcing it must not run any step.

- `step <label> [command ...]`: prints `[+Ns] <label>` on stdout; on nonzero
  status prints `FAILED: <label> (status <n>)` on stderr and appends the label
  to `FAILED_STEPS`. Returns the command's status. With `FAIL_FAST=1`, exits the
  process with that status instead of returning. With no command argument, the
  label itself is the function name (existing behavior, e.g. `step install_uv`).
- `advisory_step <label> [command ...]`: identical timing output, never records
  a failure, never exits early, always returns 0. Used only for
  `config_sync_credentials`.
- `report_failed_steps`: prints `<n> step(s) failed: <labels…>` on stderr when
  the array is non-empty and returns 1; returns 0 otherwise. Last meaningful
  command in both scripts.

Observable markers asserted by the functional test:

- stdout: `[+Ns] <label>` (unchanged format), `[+Ns] install.sh total`,
  `[+Ns] post-install.sh total`.
- stderr: `FAILED: <label> (status <n>)`,
  `<n> step(s) failed: <label> ...`.

Per-step status capture and timing format must stay identical for the existing
multi-argument calls (`step apt_update sudo apt update`,
`step chezmoi chezmoi apply --source ...`, `step versions bash ...`).

## Evidence

Load-bearing claims about the current tree:

- `step()` already captures and returns each status:
  `setup/install.sh:24-32`, `setup/post-install.sh:30-38`. Top-level calls
  ignore it (`setup/install.sh:84-168`) and the final timing `printf` leaves
  exit 0 (`setup/install.sh:170`).
- Credential sync is non-interactive-safe:
  `setup/security/credential-sync.sh:71-74`.
- Helpers are exempt from test phases 2-3 (`tests/test.sh:98,113`), but every
  setup `*.sh` is included in shellcheck (`tests/test.sh:83,135`).
- The e2e gate checks only the scripts' exit status (`tests/test.sh:200-213`);
  a repo-wide grep for the timing/`FAILED:` markers found no consumer.

## Verification

- `bash tests/setup/steps-test.sh` — hermetic runner behavior.
- `./tests/test.sh` — phases 1-4 plus existing functional tests. Helpers are
  exempt from phases 2-3; shellcheck in phase 5 covers the new helper.
- `docker compose -f tests/compose.yml run --rm test` — isolated static check.
- `./tests/test.sh --vm --reuse` — e2e. Since install.sh's exit status now
  gates the run, this also audits every step for previously silent nonzero
  returns. Use `--keep` to inspect a failing VM.

No change to dispatchers, `reports/versions.sh`, per-app scripts, or to
`tests/AGENTS.md` conventions.

## Sequencing

1. Red test: add `tests/setup/steps-test.sh` covering clean run, two
   accumulating failures with later steps still executed, `FAIL_FAST=1`
   stopping at the first failure with that step's status, advisory step exempt
   from counting and fail-fast, and a labelled command with arguments.
2. Green: add `setup/helpers/steps.sh`; replace both private `step()`s with the
   source line; switch credential sync to `advisory_step`; add the final
   `report_failed_steps || exit 1` to both scripts.
3. Document default failure behavior and `FAIL_FAST=1` in `README.md`.
4. Verify chain: static → Docker → Multipass e2e with `--keep` on failure.

## Risks

- A step currently returns nonzero on a clean VM → the e2e gate now goes red.
  That is the intended honesty: triage with `--keep`, fix a genuine bug, or
  reclassify a truly advisory step. Do not add exemptions by default.
- A counted step with a benign nonzero return would now fail the run. The e2e
  audit is the detector; reclassify such a step as advisory with a comment.
- `advisory_step` swallows credential-sync failures. That is pre-existing
  behavior made explicit; `tests/setup/security/credential-sync-test.sh` still
  covers the function's own status handling.
- `exit` inside `step()` is process-wide only because both scripts `source` the
  runner in the main shell; no step may run it in a subshell for FAIL_FAST to
  work.
- Output adds stderr lines. No in-repo consumer parses step output (e2e checks
  exit status only), so this is low risk.
