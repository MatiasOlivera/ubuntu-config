# spec.md - `110-one-e2e-run-per-vm`

## Context

Issue: [#110](https://github.com/MatiasOlivera/ubuntu-config/issues/110).

`./tests/test.sh --vm` can be started twice against the same worktree. Both runs
install into that checkout's VM at once, contend for `/var/lib/dpkg/lock-frontend`,
and produce ~120 s step timeouts and spurious `FAILED:` lines. The harness never
says that concurrency was the cause, so the result reflects neither run cleanly.

Per-worktree VM naming from #76 isolates different worktrees but not two runs on
the same one. This is a local-host verification concern; CI runners are out of
scope.

Decisions settled with the issue owner:

- A second run aimed at a VM already in use is rejected immediately with a clear
  error; no queue or wait mode.
- The guard is keyed per VM (not per host), so independent worktrees keep running
  in parallel.
- The guard releases itself when a run ends, fails, or is killed — no manual
  cleanup step.
- A rejected run must not touch the VM or alter the checkout.

## User stories

- As the maintainer, I want a second run on the same VM rejected immediately with
  a message naming the VM, so I do not wait through a run that cannot succeed.
- As the maintainer, I want only one install phase at a time in a VM, so apt lock
  contention never produces spurious `FAILED:` lines.
- As the maintainer, I want each run's result to describe only its own work, so a
  timeout caused by another run is never mistaken for a genuine install failure.
- As an agent working in several worktrees, I want runs in different worktrees to
  stay independent, so the #76 isolation still holds.
- As the maintainer, I want the guard to disappear on exit, failure or kill, so a
  crashed run never blocks the next one.
- As the test-gate maintainer, I want the guard covered by a hermetic test, so the
  static gate stays green without Multipass or network access.
- As an agent following `AGENTS.md`, I want the documented e2e workflow to state
  the guard, so there is one unambiguous command and one expected error.

## Acceptance criteria (BDD)

```gherkin
Scenario: a concurrent run is rejected before touching the VM
  Given an e2e run is actively using a checkout's VM
  When another e2e run is started against the same checkout
  Then it exits with a failure before any VM operation
  And the error names that VM and says another run is using it
  And it does not launch, start, stop, delete or execute anything in the VM
  And it leaves the checkout unchanged

Scenario: no two install phases share a VM
  Given two e2e runs are started at nearly the same time against one checkout
  When the first run takes ownership of the VM
  Then the second run is rejected
  And only the first run's install and post-install phases execute in that VM

Scenario: a rejected run does not contaminate results
  Given one run was rejected because the VM was busy
  When the run reports its outcome
  Then it reports the concurrency rejection instead of install failures
  And the accepted run's reported results come only from its own install phases

Scenario: ownership is released when a run ends
  Given a run owns a checkout's VM
  When that run finishes, fails, or is terminated
  Then a later run against the same checkout can use the VM
  And no manual cleanup of guard state is required

Scenario: different worktrees remain independent
  Given two runs target the distinct VMs of two different worktrees
  When both runs are active at the same time
  Then neither run is rejected
  And each run installs only into its own worktree's VM

Scenario: reuse and keep still work when no run is active
  Given a VM was left running by a previous --keep run
  And no e2e run is currently using it
  When a new --vm --reuse run starts
  Then it reuses that VM as before
  When a new plain --vm run starts
  Then it deletes and relaunches that VM as before

Scenario: guard machinery is unavailable
  Given the host cannot enforce the run guard
  When an e2e run starts
  Then it fails with a clear message instead of proceeding unguarded

Scenario: static gate stays green
  Given the full change is applied
  When ./tests/test.sh is run without --vm
  Then all existing checks and the new hermetic guard test pass
  And no test needs Multipass, sudo, apt, network access, or a running collector
```

## Constraints

- [ ] Scope is `tests/test.sh` plus one new guard helper and its hermetic test;
      `setup/`, `reports/`, the Python metadata tests and the observability stack
      are untouched.
- [ ] Rejection happens before any Multipass command that could alter the VM
      (launch, start, delete, transfer, exec) and before the static checks run.
- [ ] Rejection is a non-zero exit with a message naming the affected VM.
- [ ] Guard state lives outside the checkout; a run neither adds nor removes files
      in the repository and leaves nothing that needs manual cleanup.
- [ ] Guard state is keyed per VM name, so different worktrees stay independent.
- [ ] Ownership is released by the operating system when the owning process ends,
      including abnormal termination.
- [ ] The guard adds no dependency on Docker, networking, Grafana, or a collector,
      and does not change the existing per-phase timing or `[+Ns]` output format.
- [ ] New logic is covered by a hermetic test that fails when two contenders can
      own the same VM at once; no live Multipass, sudo, apt or downloads on host.
- [ ] `README.md` (Testing section) and the `run-tests` skill describe the guard
      in the same change; a decision record under `docs/decisions/` captures the
      chosen approach and the rejected alternatives.
- [ ] Out of scope: CI runners, cross-host concurrency, queue/wait mode, changing
      VM naming, changing the result format beyond the rejection message, and
      changing the observability stack.

## Assumptions

- The host provides an OS-level advisory lock that is released automatically when
  the owning process dies. Source: Linux `flock` from util-linux on Ubuntu hosts
  where Multipass runs. Verification: check `command -v flock` on the host during
  implementation; if absent, the run fails closed with the message from the
  "guard machinery is unavailable" scenario.
- Host processes see the same lock namespace for a given checkout. Source: the
  local filesystem shared by all `./tests/test.sh` invocations for that user.
  Verification: the hermetic two-contender test uses two separate processes and
  asserts exactly one winner.
