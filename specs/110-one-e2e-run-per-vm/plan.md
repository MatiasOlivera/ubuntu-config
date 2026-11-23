# plan.md - `110-one-e2e-run-per-vm`

## Architecture

Three small pieces, following the existing `tests/vm-name.sh` pattern:

1. **`tests/vm-lock.sh` (new, sourceable helper).** Defines `vm_lock_acquire
   <vm-name>`: opens a host-side lock file keyed by the VM name and takes
   exclusive, non-blocking advisory ownership. Success means the caller owns the
   VM until its process ends; failure means another live run owns it or the lock
   facility is unusable. Ownership is released by the kernel on process exit, so
   no cleanup hook is needed. A `BASH_SOURCE` guard at the bottom makes the CLI
   harmless when sourced, mirroring `tests/vm-name.sh:19-33`.
2. **`tests/vm-lock-test.sh` (new, hermetic test).** Black-box checks for the CLI
   plus source-only checks of the helper. Two separate Bash processes contend for
   one lock under a temporary `TMPDIR`; a marker file and a bounded poll replace
   timing sleeps. Assertions: exactly one winner, the loser exits non-zero with a
   VM-naming message, and a third process acquires after the holder exits. No
   Multipass, sudo, apt, downloads or network calls.
3. **`tests/test.sh` (wire-in).** The `--vm` block is `tests/test.sh:153-273`;
   `VM_NAME` is currently computed at `:159-160` and the cleanup trap installed
   at `:161`. Move name computation and lock acquisition to just after `ROOT` is
   resolved (`tests/test.sh:39-41`), so a rejected run never enters Phase 1 or
   issues a Multipass command (launch/reuse at `:174-195`, transfer at `:212-223`,
   install/post-install at `:225-255`). On failure, print an error naming
   `$VM_NAME` and `exit 1`. On success, keep the existing "e2e VM for this
   worktree" message and leave the rest of the run unchanged. The EXIT trap keeps
   deleting the VM unless `--keep`; it does not manage the lock.

Guard state lives outside the checkout (under `${TMPDIR:-/tmp}`), so a run never
dirties the repository. `flock` is checked for before use; if absent or unusable,
the run fails closed with a clear message rather than proceeding unguarded.

Docs updated in the same change: `README.md:196` (Testing section) and
`.agents/skills/run-tests/SKILL.md:53-70`, which documents VM naming and the
iteration loop. Decision recorded in `docs/decisions/0010-e2e-run-concurrency.md`.

## Data models

None. The guard uses one empty host-side file per VM name; its contents are never
read, and no schema, migration, or cleanup applies.

## API contracts

- `vm_lock_acquire <vm-name>` → exit 0 while holding VM ownership until the
  process ends; exit 1 when another live run owns that VM or when the lock
  facility cannot be used. No output on success; on failure a clear error naming
  the VM goes to stderr. Satisfies scenarios 1, 2, 4, 5 and 7 of `spec.md`.
- `tests/test.sh --vm [--keep] [--reuse]` → unchanged CLI. New early failure path:
  non-zero exit plus an error naming the VM, before any VM operation. Satisfies
  scenarios 1 and 6.
- Existing console formats from `setup/helpers/steps.sh` (`[+Ns] <label>`,
  `FAILED: <label> (status n)`) stay byte-for-byte unchanged; specs 030 and 082
  depend on them.

## Decisions

- `docs/decisions/0010-e2e-run-concurrency.md` (accepted, 2026-11-23): one active
  run per VM, fail fast, per-VM scope, OS-managed release. Rejected: blocking
  wait, opt-in wait flag, host-wide lock, VM-state inference, no guard.

## Risks

- **Child processes extending ownership.** A lock fd inherited by a long-lived
  child could outlive the run. Mitigation: the harness starts no background work
  (`tests/e2e-observability.sh:28-49`), and the helper should ensure the fd does
  not leak to commands; the hermetic test asserts a new owner after the holder
  exits.
- **Missing lock facility.** `flock` is present on the target host
  (`/usr/bin/flock`, util-linux 2.41.3), but a different host may lack it.
  Mitigation: fail closed with the documented message.
- **Lock-key collision.** `tests/vm-name.sh:29-33` derives the VM name from the
  full checkout path, so separate worktrees get separate lock files. Two paths
  producing the same name would also share a VM, so rejecting them is correct.
- **Trap interaction.** The EXIT trap may delete the VM while a kept VM is
  intentionally preserved. The lock is independent of the trap and is released
  by the kernel even if the trap does not run, so no stale state remains.
- **Scope creep.** Wait mode, CI coverage, VM naming and result formatting are
  explicitly out of scope; the diff stays inside the test harness, one helper,
  one test, docs and the ADR.

## Assumptions

- The host provides `flock` (util-linux). Source: `command -v flock` →
  `/usr/bin/flock`, version 2.41.3 on this host. Verification: re-check at
  implementation time and fail closed if missing.
- All processes for a checkout see the same lock namespace. Source: the shared
  local filesystem used by every `./tests/test.sh` invocation. Verification: the
  two-process contention test must yield exactly one winner.
- A checkout's e2e run uses the single VM name from `tests/vm-name.sh`.
  Source: `tests/test.sh:159-200` uses `VM_NAME` for every Multipass operation.
  Verification: code review during implementation plus the existing
  `tests/vm-name-test.sh` contract.
