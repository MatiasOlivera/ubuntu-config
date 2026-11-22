# spec.md - `080-cursor-apt-source-rerun`

## Context

Issue: [#80](https://github.com/MatiasOlivera/ubuntu-config/issues/80).

Cursor IDE is installed from the vendor's apt repository, which this repo
registers before its single `apt update`. The Cursor `.deb` also registers that
same repository during its own installation, using its own signing-key path. On
a machine where Cursor was installed once, a later setup run re-creates this
repo's source entry next to the package-owned one. `apt update` then sees two
entries for the same source with different `Signed-By` values, exits 100, and —
since #30 — fails the run before any later step is attempted. The same conflict
appears when the e2e gate reuses an already-configured VM (surfaced by the #30
audit).

This breaks constitution axioms 1 (no environment fact configured twice by
different layers) and 2 (reruns converge; failures stop loudly).

Design decisions settled with the issue owner:

- Adopt the package's own source layout as the single canonical entry: the
  repository step produces the same source and key the package would, so both
  ownership paths yield an identical result.
- A rerun must converge even from the already-broken state where both entries
  exist.
- Rejected: keeping this repo's source authoritative and suppressing the
  package's registration through a debconf preseed (couples to a package-specific
  question); skipping our source when the vendor entry exists (two owners, weak
  on partially configured machines); dropping apt for Cursor IDE (larger change,
  lower install-method rung).
- Scope: the Cursor source only. A shared helper that guards every vendor apt
  source against the same class of conflict is tracked in follow-up issue
  [#100](https://github.com/MatiasOlivera/ubuntu-config/issues/100), so this fix
  stays a single atomic change.

## User stories

- As a person rerunning setup, I want `apt update` to succeed on my
  already-configured machine, so a rerun does not fail before later apps are
  installed.
- As a person who installed Cursor through this repo, I want exactly one Cursor
  apt source with one signing key, so apt does not report a conflicting option.
- As a person reusing an e2e VM, I want setup to converge from the state left by
  the previous run, so the reuse loop exercises a real rerun.
- As a person tracking what the repo owns, I want the Cursor package and the repo
  to configure the same fact in the same way, so there is one source of truth.

## Acceptance criteria (BDD)

```gherkin
Scenario: first run configures one canonical Cursor source
  Given a fresh machine with no Cursor apt source or key
  When setup registers repositories and runs apt update
  Then apt update succeeds
  And exactly one apt source entry exists for the Cursor apt repository
  And that entry names /usr/share/keyrings/anysphere.gpg as its signing key

Scenario: rerun after the Cursor package installed converges
  Given a previous run installed the Cursor package, which registered its own source
  When setup registers repositories and runs apt update again
  Then apt update succeeds
  And exactly one apt source entry exists for the Cursor apt repository
  And its signing key is unchanged from the one the package registered

Scenario: rerun from the already-broken state repairs the machine
  Given two conflicting entries for the Cursor repository exist from an earlier run
  When setup registers repositories and runs apt update again
  Then the stale entry and its key are gone
  And exactly one apt source entry remains for the Cursor repository
  And apt update succeeds

Scenario: the Cursor install path still works
  Given the canonical Cursor source is configured
  When setup reaches the Cursor install steps
  Then the Cursor package installs successfully
  And a later run skips it with the installed version

Scenario: unrelated apt sources and reports are unchanged
  Given the other vendor repositories are configured
  When the Cursor source is rewritten on a rerun
  Then every other apt source file is byte-for-byte unchanged
  And the versions report still reports the Cursor install correctly
```

## Constraints

- [ ] The repository step remains source-only and side-effect-free when sourced;
      it writes files only when invoked.
- [ ] Other repository functions, the single `apt update` step and the step
      ordering in `setup/install.sh` stay as they are.
- [ ] Install-method priority stays on the vendor apt repository rung; no new
      dependency, artifact download or integrity exception.
- [ ] Verification is hermetic per `tests/AGENTS.md`: curl, gpg, sudo and file
      paths are stubbed; no network or host system changes.
- [ ] Public repo: no secrets, no new credential files outside apt keyrings.
- [ ] Shared apt-source helper is out of scope; tracked in issue #100.

## Assumptions

- The key embedded in the Cursor package is the same key published at
  `https://downloads.cursor.com/keys/anysphere.asc` — verified 2026-11-22 by
  comparing `gpg --show-keys` fingerprints (both
  `380FF4BCDC34A4BD92A3565342A1772E62E492D6`). No verification step needed.
- Ubuntu 26.04's apt accepts DEB822 `.sources` files — the package's own
  postinst writes one there; e2e `--vm --reuse` confirms it in context.
