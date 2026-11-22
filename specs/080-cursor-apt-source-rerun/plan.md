# plan.md - `080-cursor-apt-source-rerun`

## Architecture

One setup function changes; no new component, dependency or step.

```
setup/development/cursor.sh
  install_cursor_repository()   [called once per run, before apt update]
    ├─ install key  -> /usr/share/keyrings/anysphere.gpg
    ├─ write source -> /etc/apt/sources.list.d/cursor.sources (DEB822)
    └─ remove stale -> /etc/apt/sources.list.d/cursor.list
                       /etc/apt/keyrings/cursor.gpg

setup/install.sh
  repositories phase (unchanged order) -> step apt_update sudo apt update
  -> Cursor install steps (unchanged, version-gated)
```

Both ownership paths now produce the same fact. The Cursor `.deb` postinst
writes the same DEB822 file and key and removes `cursor.list`; when the package
is later installed or upgraded, it rewrites an identical file. On rerun the
repo function overwrites that file with the same bytes, so `apt update` sees one
entry with one `Signed-By`. Removing the legacy `.list` and key in the same
function repairs machines already in the broken state.

Rejected (recorded in spec.md): debconf preseed to suppress the package's
registration; "skip if vendor source exists" guard; leaving apt for a raw
artifact. No new ADR: this is a bug fix, not a stack, protocol or workflow
choice; the approach is settled with the issue owner in the spec.

## Data models

None. The only state is the two apt files and the keyring file above; no new
variables, arrays or persisted metadata.

## Interface contracts

`install_cursor_repository` stays side-effect-free on `source` and keeps its
name and zero-argument signature, so `setup/install.sh`, the dispatcher's
`repository` command and `tests/test.sh`'s source-only check are unaffected.

Observable file contract asserted by the hermetic test:

- `/etc/apt/sources.list.d/cursor.sources` exists and contains exactly:
  `Types: deb`, `URIs: https://downloads.cursor.com/aptrepo`, `Suites: stable`,
  `Components: main`, `Architectures: amd64,arm64`,
  `Signed-By: /usr/share/keyrings/anysphere.gpg`.
- `/etc/apt/sources.list.d/cursor.list` and `/etc/apt/keyrings/cursor.gpg` do
  not exist after the function runs, even if they existed before.
- Running the function twice leaves `cursor.sources` byte-for-byte identical.
- Files belonging to other repositories are not read or modified.

`apt update` itself is not run by the function; ordering in `install.sh` stays
as-is.

## Decisions

- Approach: mirror the vendor package's canonical source (spec.md, "Context").
  No ADR — see Architecture above.
- Scope: Cursor only; shared helper filed as issue #100.

## Evidence

- Current function writes the conflicting `.list` entry at
  `setup/development/cursor.sh:23-26`; it runs every time at
  `setup/install.sh:92`, before the single `apt update` at
  `setup/install.sh:99`. The Cursor install is version-gated at
  `setup/development/cursor.sh:14-21`, so reruns skip the package but never skip
  the repository function.
- Root cause observed 2026-11-22 from the package control archive:
  `curl -r 0-262143 .../pool/stable/c/cu/cursor_3.31.15_amd64.deb -o part.deb &&
  dpkg-deb -e part.deb ctrl` → `ctrl/postinst` registers
  `/etc/apt/sources.list.d/cursor.sources` with
  `Signed-By: /usr/share/keyrings/anysphere.gpg`, removes `cursor.list`, and
  writes that key when absent. This matches the error text in issue #80.
- The embedded key and `https://downloads.cursor.com/keys/anysphere.asc` have
  the same fingerprint `380FF4BCDC34A4BD92A3565342A1772E62E492D6`
  (`gpg --show-keys --with-colons` on both), so the repo can install the key
  itself without a second trust decision.
- No other script references `cursor.list` or `cursor.gpg` (repo-wide grep).
- Test conventions and stub patterns: `tests/AGENTS.md` and
  `tests/setup/development/fnm-test.sh`.

## Verification

- `bash -n setup/development/cursor.sh` and `shellcheck -e SC1091 setup/development/cursor.sh`.
- `bash tests/setup/development/cursor-test.sh` — hermetic (stub curl, gpg,
  sudo, tee, rm; sandboxed paths), no network or host changes.
- `./tests/test.sh` — full static gate (source-only check, dispatch, shellcheck).
- `docker compose -f tests/compose.yml run --rm test` — isolated static check.
- `./tests/run-with-logging.sh e2e ./tests/test.sh --vm --keep` then
  `./tests/run-with-logging.sh e2e ./tests/test.sh --vm --reuse` — the reuse run
  reproduces issue #80's rerun path on an already-configured VM.
- No change needed to `reports/versions.sh` or `README.md`: function names,
  step order and user-facing commands are unchanged.

## Sequencing

1. Red: add `tests/setup/development/cursor-test.sh` with the five behavior
   cases (fresh, vendor-rewritten rerun, broken-state repair, idempotence,
   source-only/other-sources-untouched). It fails against the current tree.
2. Green: rewrite `install_cursor_repository()` in `setup/development/cursor.sh`
   to install the `anysphere.gpg` key, write the DEB822 `cursor.sources`, and
   remove the legacy `.list` and key. Keep `install_cursor*` and version guards
   untouched.
3. Run the static gate and isolated Docker check.
4. Run the e2e seed/reuse chain through the log-capture runner; inspect a kept
   VM on failure.
5. Follow-up issue #100 tracks the shared apt-source helper (filed; no code
   here).

## Risks

- DEB822 `.sources` must be understood by the target apt. Ubuntu 26.04's
  package postinst already writes one, so this is the vendor's own format;
  `--vm --reuse` verifies it in context.
- The vendor may change its registered path or key again. The repo then writes
  its canonical file while the package writes a different one — issue #100's
  shared helper addresses the class of bug; e2e reuse is the detector.
- Deleting `/etc/apt/keyrings/cursor.gpg` affects anyone who manually referenced
  that path; the repo owns that file, and no in-repo consumer uses it.
- Stubbed tests cannot prove apt's conflict resolution. The reused-VM e2e run is
  the behavioral proof; do not skip it for install-path changes.
