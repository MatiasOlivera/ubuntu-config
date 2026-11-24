# tasks.md - `078-speed-up-e2e-verification`

> Atomic, dependency-ordered, each independently verifiable.

| ID  | Done | Task | Depends on | Type | Verification |
| --- | ---- | ---- | ---------- | ---- | ------------ |
| 1   | [x]  | Write a hermetic test asserting one phase span per phase, correct name/kind/duration/status, no emission when observability is off, and no phase row in the summary (red) | - | Automated | `bash tests/observability/phase-span-test.sh` failed before the helper existed |
| 2   | [x]  | Add `observability_phase_begin`/`observability_phase_end` to the observability helper | 1 | Automated | `bash tests/observability/phase-span-test.sh` passes |
| 3   | [x]  | Emit phase spans from `install.sh` and `post-install.sh` at their existing total timers | 2 | Automated | hermetic test + `./tests/test.sh` static checks |
| 4   | [x]  | Add the `run_id` variable and per-run phase-total panel to the existing dashboard | 3 | Manual | query returns one value per run from a phase span (verified against Loki) |
| 5   | [x]  | Add call-type and package-manager-tool panels; sort the slowest-steps and download-host bar gauges descending; show the per-run total as a table | 4 | Manual | queries return series from replayed records; panels verified visually in Grafana |
| 6   | [x]  | Add the new record-backed queries to the Grafana cookbook | 4 | Manual | cookbook queries match the panel queries and return data |
| 7   | [x]  | Run the full static gate | 1-6 | Manual | `./tests/test.sh` exits 0 |
| 8   | [x]  | Run an e2e VM verification and compare the phase span with the console total | 7 | Manual | `./tests/test.sh --vm --keep`; 583607 ms vs `[+584s]` and 18145 ms vs `[+18s]` |
| 9   | [x]  | Benchmark checkout shipping and record collection on one warm VM: tarball transfer, `classic` mount, `native` mount | 8 | Manual | transfer 551 ms, classic setup 659 ms + copy 594 ms, records 571 ms vs 837 + 233 ms; native needs a stopped VM |
| 10  | [x]  | Benchmark a clean install at a second resource allocation | 8 | Manual | 4 CPU / 8 G: 520 s vs 2 CPU / 4 G: 564 s, single sample each |
| 11  | [x]  | Locate the real cause of the warm-run gap and record the decision with the measurements | 9, 10 | Manual | ADR records the inherited keepalive stream and the rejected alternatives |
| 12  | [ ]  | Write a hermetic regression test that fails while either keepalive loop inherits an output stream (red) | 11 | Automated | new test fails before the stream fix |
| 13  | [ ]  | Redirect the keepalive streams in `install.sh` and `post-install.sh` | 12 | Automated | regression test passes; `./tests/test.sh` static checks |
| 14  | [ ]  | Run the static gate and a warm `--reuse` run, and record before/after timings | 13 | Manual | `./tests/test.sh` exits 0; 105 s before, new timing recorded |
| 15  | [ ]  | Update agent-facing docs only if the repeat-run workflow description changes | 14 | Manual | documented `--reuse` command still matches the harness |
