# spec.md - `077-e2e-observability`

## Context

Issue: [#77](https://github.com/MatiasOlivera/ubuntu-config/issues/77), milestone
`v0.5.0 - foundations: policy decisions`.

The Multipass e2e run in `tests/test.sh` reports only aggregate per-phase
wall-clock time; the two install phases are single opaque `multipass exec`
calls. The setup scripts already time each step, but those timings and the
`FAILED:` lines stream to the console and are discarded, so a failure cannot be
attributed to an app after the run, and runs cannot be compared. The only log
capture is `tests/run-with-logging.sh`, which produces one file for the entire
run; keeping it alongside the new stack would mean two ways to record logs.

The run is local-only by design. The maintainer needs durable, inspectable
records that answer: which app failed, how long each app took, and — critically
for #78 — how much of that time was downloading versus installing.

Design decisions settled with the issue owner:

- Use a full OpenTelemetry-based local stack: Collector, Tempo (traces), Loki
  (logs), Prometheus (metrics), Grafana (UI). Traces and spans are the primary
  model; logs correlate to spans; metrics give cross-run history.
- Hybrid data path: durable files are always written to an
  `E2E_OBSERVABILITY_DIR`-controlled location, and the same data is forwarded
  live to a host collector on a best-effort basis. Files are the source of
  truth; an unreachable collector must never break or invalidate a run.
- Signals in scope: one span per install/config step; download child spans;
  package-manager spans; network byte counters; per-app disk bytes; run
  metadata. Spans carry a log reference so a failed app's logs are reachable
  from the trace.
- Disk bytes come from a per-app manifest of install paths measured with `du`,
  plus a cheap `dpkg-query` delta for apt packages; one generic filesystem
  delta is taken per run as a cross-check, never per step (a real-host snapshot
  cost ~7 s in the spike and would skew the timings). The manifest is a
  maintained artifact, checked by a test that each path resolves after its
  step; sizes are reported as approximate because shared dependencies can be
  double-counted.
- Host metadata (hostname, host OS, host CPU/RAM/load) is explicitly out of
  scope: the VM configuration is fixed and host details add no actionable
  signal for optimizing installs. Keep only run id, timestamp, git
  commit/branch, VM name, and Ubuntu image.
- CPU/RSS resource accounting is out of scope for this issue.
- `tests/run-with-logging.sh` and its test are removed; the stack becomes the
  single way to record e2e logs. `reports/*.sh` stay unchanged.
- The stack is started manually by the maintainer/agent following the documented
  command in `AGENTS.md`; `tests/test.sh` does not manage container lifecycle.
- Accepted limitations: `apt`/`snap`/`flatpak` perform download and install
  inside one command, so their spans cannot split the two without syscall
  tracing or rewriting installer code; that is not done here.
- Rejected: marker-parsing of the console transcript (no spans, no log
  correlation, no metrics); in-VM-only instrumentation without a stack (no UI
  or cross-run analysis); file-only OTel (no live views); live-only OTLP (loses
  data on failure and depends on VM-to-host networking); generic per-step
  filesystem snapshots (too slow, skews timings); replacing `reports/*.sh`
  with metrics (unrelated, much larger change).

## User stories

- As the maintainer, I want one span per app install step showing status and
  duration, so a failed e2e run immediately names the app and its cost.
- As the maintainer, I want download and install shown separately per app, so I
  can tell whether a slow run is network-bound or installation-bound.
- As the maintainer, I want to click a failed span and read that app's logs, so
  I can diagnose the failure without re-running the whole suite.
- As the maintainer, I want network bytes, disk bytes and package-manager calls
  recorded per step, so an optimization can be chosen from evidence rather than
  guesswork.
- As the maintainer, I want every run's spans, logs, and metrics persisted in a
  directory I control, so I can compare runs days or weeks later.
- As the maintainer, I want the option to watch spans arrive live while a run is
  in progress, without making live delivery a condition of the run's success.
- As an agent following `AGENTS.md`, I want one documented command to start the
  local stack and one logging workflow, so there is no ambiguity about where
  records go.
- As a maintainer of the test gate, I want the new instrumentation to be
  hermetically tested and the existing static checks to stay green.

## Acceptance criteria (BDD)

```gherkin
Scenario: a completed e2e run leaves durable per-app records
  Given a Multipass e2e run completes with E2E_OBSERVABILITY_DIR set
  When the run finishes
  Then the directory contains one record for each install/config step
  And each record shows the step's outcome and wall duration
  And a run-level summary lists every step in execution order
  And no record file is written inside the repository

Scenario: download and install are distinguishable per app
  Given an app whose install fetches a release artifact and then installs it
  When the maintainer inspects that app's trace
  Then a download child span shows the fetch duration and bytes transferred
  And the parent step span shows the total duration
  And the time outside the download child span is attributable to install

Scenario: package-manager time is visible
  Given an app installed through apt, snap, or flatpak
  When the maintainer inspects that app's trace
  Then the package-manager call appears as a child span with its duration
  And the span is marked as bundling download and install

Scenario: disk footprint is recorded per app
  Given a manifest of install paths for the apps in the run
  When each app finishes installing
  Then its record reports the bytes used by its declared paths
  And apt-installed apps report the size delta from the package database
  And the sizes are marked as approximate
  And one run-level filesystem delta is recorded as a cross-check
  And a test fails when a declared path no longer resolves after its step

Scenario: a failed app's logs are reachable
  Given an install step returns nonzero during an e2e run
  When the maintainer opens the run's trace in the stack
  Then that step's span is marked as failed with its exit status
  And selecting the span shows the log lines emitted by that step
  And the same log lines exist in the durable record directory

Scenario: live delivery is best effort
  Given the host collector is reachable from the VM
  When the e2e run executes
  Then spans and log lines appear in the stack while the run is in progress
  Given the host collector is not reachable
  When the e2e run executes
  Then the run completes normally with all records written to disk
  And the harness reports that live delivery was unavailable

Scenario: the stack exposes traces logs and metrics
  Given the maintainer started the stack with the documented AGENTS.md command
  When the durable records from a run are ingested
  Then traces group spans by run and by app
  And logs are searchable and correlated to their span
  And metrics show per-app duration and outcomes across runs

Scenario: record location and retention
  Given E2E_OBSERVABILITY_DIR points to a chosen path
  When runs are executed repeatedly
  Then each run writes to its own subdirectory under that path
  And the default path is under the user's home directory
  And records remain until the maintainer deletes them
  And no records are committed to the repository

Scenario: one logging workflow
  Given the observability stack is the logging workflow
  When an agent or maintainer follows AGENTS.md
  Then tests/run-with-logging.sh no longer exists
  And AGENTS.md and the run-tests skill describe only the stack-based workflow
  And the reports scripts are unchanged

Scenario: static checks stay green
  Given the full change is applied
  When ./tests/test.sh is run without --vm
  Then all static and functional checks pass
  And new behavior is covered by hermetic tests with no network or system calls
```

## Constraints

- [ ] Scope is the Multipass e2e run only: `tests/test.sh`, the setup step
      runner and installers, new observability assets, and docs. `reports/*.sh`
      and the Python metadata tests are untouched.
- [ ] `tests/run-with-logging.sh` and `tests/run-with-logging-test.sh` are
      deleted, along with references in `AGENTS.md` and the run-tests skill.
- [ ] Durable records are controlled by `E2E_OBSERVABILITY_DIR`, defaulting to
      `${XDG_DATA_HOME:-$HOME/.local/share}/ubuntu-config/observability/<run-id>/`;
      one subdirectory per run, kept until manually deleted, never committed.
- [ ] A per-app install-path manifest is part of the change, tested for drift;
      disk sizes are labeled approximate and no generic snapshot runs per step.
- [ ] Records are written on the host even when the VM is deleted by the e2e
      cleanup trap.
- [ ] Live forwarding uses a host address supplied by the harness and is
      best-effort; it must not add a hard dependency on Docker, networking, or a
      running collector to the e2e gate.
- [ ] The chosen option and its rejected alternatives are recorded in an MADR
      decision record under `docs/decisions/`.
- [ ] The existing `[+Ns] <label>` and `FAILED: <label> (status n)` console
      output of `setup/helpers/steps.sh` keeps its exact format; specs 030 and
      082 depend on it and the functional tests assert it.
- [ ] Instrumentation is source-only where it lives in setup helpers, stays
      shellcheck-clean, and does not disturb the sudo keepalive or EXIT traps.
- [ ] No host metadata, no CPU/RSS accounting, no syscall tracing, and no
      changes to per-app download/integrity behavior.
- [ ] New logic is covered by hermetic tests: no live network, sudo, apt, or
      system-mutating setup runs on the host.
- [ ] Long e2e runs are never piped to `head` or `tail` (SIGPIPE can trigger the
      VM cleanup trap).

## Assumptions

- The host has Docker Compose available (`docker compose version` → v5.8.0 on
  this host) and the OpenTelemetry images can be pulled locally. Verification:
  run the documented stack command once before the e2e run.
- Bash can emit OTLP over HTTP with `curl` and the Collector accepts OTLP/HTTP
  JSON. Source: OpenTelemetry OTLP/HTTP specification. Verification: hermetic
  integration test against a stub HTTP endpoint before the first e2e run.
- A Multipass VM can reach an address supplied by the harness. Source: Linux
  QEMU user networking on this host. Verification: a one-line reachability
  check in the e2e path; failure falls back to file-only as specified.
- A generic filesystem snapshot costs seconds on this host (`du` over
  `/usr/local`, `/snap`, flatpak dirs took ~7.2 s; `dpkg-query` took ~19.6 ms).
  Source: read-only spike run during this spec's investigation. Verification:
  rerun the spike before implementation; if snapshots become cheap, revisit
  the one-per-run limit.
