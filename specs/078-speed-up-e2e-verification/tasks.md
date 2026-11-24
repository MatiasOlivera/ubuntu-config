# tasks.md - `078-speed-up-e2e-verification`

> Atomic, dependency-ordered, each independently verifiable.

| ID  | Done | Task | Depends on | Type | Verification |
| --- | ---- | ---- | ---------- | ---- | ------------ |
| 1   | [x]  | Write a hermetic test asserting one phase span per phase, correct name/kind/duration/status, no emission when observability is off, and no phase row in the summary (red) | - | Automated | `bash tests/observability/phase-span-test.sh` failed before the helper existed |
| 2   | [x]  | Add `observability_phase_begin`/`observability_phase_end` to the observability helper | 1 | Automated | `bash tests/observability/phase-span-test.sh` passes |
| 3   | [x]  | Emit phase spans from `install.sh` and `post-install.sh` at their existing total timers | 2 | Automated | hermetic test + `./tests/test.sh` static checks |
| 4   | [x]  | Add the `run_id` variable and per-run phase-total panel to the existing dashboard | 3 | Manual | query returns one value per run from a phase span (verified against Loki) |
| 5   | [x]  | Add call-type, package-manager-tool and download-host panels; sort the slowest-steps bar gauge descending while keeping its styling | 4 | Manual | all four queries return series from replayed records; bar gauge verified visually in Grafana |
| 6   | [x]  | Add the new record-backed queries to the Grafana cookbook | 4 | Manual | cookbook queries match the panel queries and return data |
| 7   | [x]  | Run the full static gate | 1-6 | Manual | `./tests/test.sh` exits 0 |
| 8   | [ ]  | Run one e2e VM verification and compare the phase span with the console total | 7 | Manual | `./tests/test.sh --vm --keep`; span duration matches `[+Ns] ... total` |
