# tasks.md - `030-surface-failed-install-steps`

| ID  | Done | Task | Depends on | Type      | Verification |
| --- | ---- | ---- | ---------- | --------- | ------------ |
| 1   | [x]  | Add `tests/setup/steps-test.sh`: hermetic tests for a clean run, two accumulating failures with later steps still executed, `FAIL_FAST=1` stopping at the first failure with that step's status, an advisory step exempt from counting and fail-fast, and a labelled command with arguments. | - | Automated | `bash tests/setup/steps-test.sh` fails against the current tree (no shared runner) — the red state before task 2. |
| 2   | [x]  | Add `setup/helpers/steps.sh` with `step`, `advisory_step` and `report_failed_steps`; replace both scripts' private `step()` with the source line, switch `config_sync_credentials` to `advisory_step`, and end both scripts with `report_failed_steps \|\| exit 1`. | 1 | Automated | `bash tests/setup/steps-test.sh` passes and `./tests/test.sh` phases 1-5 pass on a trusted checkout. |
| 3   | [x]  | Document default failure behavior and `FAIL_FAST=1` in `README.md`. | 2 | Manual | README states all steps run, a summary plus nonzero exit reports failures, and credential sync stays advisory. |
| 4   | [x]  | Run the isolated static verification. | 2 | Automated | `docker compose -f tests/compose.yml run --rm test` passes. |
| 5   | [ ]  | Audit all steps on a clean VM and verify the e2e gate. | 4 | Manual | `./tests/test.sh --vm --reuse` passes; previously silent nonzero steps are triaged (fixed or reclassified advisory with a comment). Use `--keep` to inspect failures. |
