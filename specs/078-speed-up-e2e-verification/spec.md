# spec.md - `078-speed-up-e2e-verification`

## Context

Issue: [#78](https://github.com/MatiasOlivera/ubuntu-config/issues/78). Reduce the
wall-clock time of the Multipass end-to-end verification run, choosing where to
optimize from measured data rather than guesswork. #77's observability work is
available: per-app spans, logs and summaries are written per run and replayed
into a local Grafana stack.

**Phase 1 — measurement (done).** Review of fresh-run records showed:

| Run | `install.sh` | apt / apt-get | direct downloads | flatpak + snap |
| --- | --- | --- | --- | --- |
| A | 822s | **544s (66%)** | 133s | 99s |
| B | 2451s | **2171s (89%)** | 136s | 102s |
| C | 767s | **300s (39%)** | 285s | 135s |

apt calls dominated, so the per-run total, descending slow-step ranking,
call-type split and host breakdown were added to the dashboard. Two further e2e
runs (541s and 584s installs) confirmed the phase spans match the console
markers within a second.

**Why a package cache was rejected.** The span logs show apt transferring bytes
fast: 295 MB in 8 s, 88.7 MB in 2 s, 179 MB in 5 s, and 12.1 MB of metadata in
2 s. The long apt steps are dpkg unpack/configure and service restarts, not wire
time, so caching downloaded packages would save seconds, not minutes.

**Phase 2 — the optimization (this change).** A warm VM runs the scripts in
~21 s (20 s install + 2 s post-install), but the whole `--reuse` run took
~105 s. Investigation showed the gap is not the number of remote calls: a bare
`multipass exec` takes ~0.2 s, and the wrapper including record copying takes
~2 s. The real cause is stream ownership — both setup scripts start a sudo
keepalive loop whose stdout is inherited, so when the script exits, an orphaned
`sleep 50` holds the pipe open and the exec waits for EOF. Reproduced directly:
an orphaned 15 s sleep made an exec take 15.2 s. After redirecting the loop's
streams inside the VM, an install exec took 17.4 s against a 17 s script total
(a ~0.4 s gap). The optimization is therefore a two-line stream fix, not a
harness rewrite.

**Measured sub-choices.** The tarball transfer took ~0.55 s and a `classic`
mount ~0.66 s setup + ~0.59 s copy-in; `native` mounts require a stopped VM, so
they are unavailable for a warm run. Record collection was ~0.57 s via tar +
transfer versus ~0.84 s setup + ~0.23 s copy over a mount. Neither changes the
~80 s cost, so the harness keeps its single transfer and adds no persistent
mount. A clean install at 4 CPUs / 8 G took 520 s versus 564 s at 2 CPUs / 4 G
in a single sample — a possible ~8 % win, but not enough evidence to change the
VM defaults.

This spec covers both phases. The decision and its measurements are recorded in
ADR `0014-repeat-run-round-trips.md`.

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
- As the maintainer, I want a phase command to return as soon as its script
  finishes, so a background helper cannot add tens of seconds to every run.
- As the maintainer, I want the phase markers, failure reporting and record
  copying unchanged after the fix, so a faster run is not a less trustworthy
  one.
- As the maintainer, I want before/after timings for the repeat path, so the
  optimization is proven rather than assumed.
- As the maintainer, I want the transfer-versus-mount comparison recorded, so a
  later reader does not re-litigate a measured choice.
- As the maintainer, I want the resource-sizing comparison recorded, so any
  future change of VM defaults is based on more than one sample.
- As the maintainer, I want the measured sub-choices recorded, so a later reader
  knows why the harness uses its current mount and VM size.
- As the test-gate maintainer, I want the call reduction covered by a hermetic
  test, so a regression fails without Multipass or a VM.

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

Scenario: a phase command returns when its script finishes
  Given a warm VM and an install phase whose script finishes in N seconds
  When the harness waits for that phase command to return
  Then the command returns within a small margin of N seconds
  And no background helper keeps the command's output stream open

Scenario: a failed phase still fails the run
  Given an install phase that fails in the VM
  When the harness reports the outcome
  Then the run fails with the failing step named
  And it does not proceed as if the phase succeeded

Scenario: records are copied once even on failure
  Given an install phase that fails after emitting spans
  When the run ends
  Then the records are copied back exactly once
  And the summary still lists the steps that ran

Scenario: fresh runs are unchanged
  Given no VM exists for the checkout
  When a plain --vm run starts
  Then launch, cloud-init and the base snapshot still happen
  And install, post-install, smoke and repository validation still run as before

Scenario: normal setup is unaffected
  Given a normal setup run without an observability record directory
  When install.sh runs
  Then no spans are emitted and its output is unchanged

Scenario: mount and transfer are compared on the same checkout
  Given a warm VM and a checkout of known size
  When I time the current tarball transfer and a persistent mount for both shipping the checkout and collecting records
  Then both measurements are recorded with the same VM and the same commands
  And the harness keeps the transfer because no mount showed a meaningful win

Scenario: resource sizes are compared on the same install
  Given an otherwise identical e2e run
  When I run it with different CPU and memory allocations
  Then the install duration and total wall-clock time are recorded for each size
  And the VM defaults stay unchanged until more samples justify a change

Scenario: the repeat speedup is measured
  Given a before timing from a warm --reuse run
  When the stream fix is applied and the same scenario is run again
  Then the wall-clock time is recorded with the same checks passing

Scenario: static gate stays green
  Given the full change is applied
  When ./tests/test.sh is run without --vm
  Then all existing checks pass without a running stack, Multipass, sudo, or network access
```

## Constraints

- [ ] Phase 1 scope was the provisioned dashboard, observability helper, both
      setup entry scripts, the cookbook and hermetic emission tests; it is done.
- [ ] Phase 2 scope is the two stream redirections in `setup/install.sh` and
      `setup/post-install.sh`, one hermetic regression test, the e2e harness
      only if the measured fix requires it, and agent-facing docs if the
      workflow changes. No dashboard, CI workflow or VM naming changes.
- [ ] The stream fix applies to every setup run, while the measured win is
      largest on repeat runs; fresh `--vm` runs keep launch, cloud-init,
      snapshot, install and all repository/release validation.
- [ ] The `[+Ns]` phase markers, `fail`/`pass` accounting, lock guard, and record
      copying on success and failure must behave exactly as before.
- [ ] No new dependency, no VM snapshot change, no new secrets; the static gate
      remains zero-dependency and offline.
- [ ] No persistent mount: the measured data movement is under a second for both
      paths, and `native` mounts require a stopped VM.
- [ ] VM defaults stay at 2 CPUs / 4 G / 50 G until more than one sizing sample
      justifies a change.
- [ ] A before/after timing for a warm --reuse run must be recorded, along with
      the mount/transfer and resource-size comparison data.
- [ ] Out of scope: package/artifact caches, a local registry, snapshot-based
      warm starts, parallel apt installs, CI runners, and changes to the
      observability stack.

## Assumptions

- A Multipass `exec` waits for EOF on its output streams, so a background
  process that inherits stdout delays the call until that process exits.
  Source: reproduction with an orphaned 15 s sleep (15.2 s exec) and a 17.4 s
  exec against a 17 s script after the stream fix. Verification: the before and
  after warm-run timings.
- The keepalive loop's inherited stdout is the stream holding the pipe open.
  Source: the two setup entry scripts and an in-VM patch that reduced the gap
  from 31–50 s to ~0.4 s. Verification: hermetic regression test and a real
  `--reuse` run.
- Data movement is under a second for both transfer and classic mount, and a
  native mount requires a stopped VM. Source: the mount/transfer benchmark in
  this change; official mount docs for the `$HOME` and overlay caveats.
  Verification: the recorded comparison numbers.
- More CPU and memory gave 520 s versus 564 s in one sample. Source: the sizing
  experiment on a fresh 4 CPU / 8 G VM versus the 2 CPU / 4 G seed run.
  Verification: repeat the sizing run before changing VM defaults.
- Replayed spans reach Loki through `filelog/spans` + `json_parser` and `| json`
  exposes the span fields used by the dashboard. Source:
  `tests/observability/collector-config.yml` and the cookbook queries.
- Replayed records share an ingest timestamp, so panel queries use bounded
  windows. Source: the dashboard JSON and the cookbook replay caveat.
