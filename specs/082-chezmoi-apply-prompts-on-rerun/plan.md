# plan.md - `082-chezmoi-apply-prompts-on-rerun`

## Architecture

Two call sites change; no step moves between scripts and no dotfile content changes.

```
setup/install.sh:158
  step chezmoi chezmoi apply --force --source "$DOTFILES_DIR"
    - identity block (144-156) unchanged
    - every other step and both timing/report lines unchanged

setup/development/oh-my-zsh/oh-my-zsh.sh:11
  install_oh_my_zsh()
    - version guard (skip when ~/.oh-my-zsh exists) unchanged
    - installer call gains: "" --keep-zshrc --unattended
        --keep-zshrc  -> upstream setup_zshrc() returns early:
                         ~/.zshrc is never backed up or replaced
        --unattended  -> CHSH=no, RUNZSH=no, OVERWRITE_CONFIRMATION=no:
                         no shell-change prompt, no exec zsh -l

tests/setup/dotfiles-convergence-test.sh (new, hermetic)
  - stub curl -> fake installer records its "$@"; assert both flags
  - assert the installed guard skips the installer
  - assert install.sh's chezmoi step carries --force
```

Resulting convergence: the declarative file is written first and is never
rewritten by the imperative installer, so a rerun sees an unchanged target.
`--force` additionally makes any other locally modified managed dotfile converge
without a prompt.

## Data models

None. No persisted state, schema, or format changes; chezmoi's own target-state
tracking stays as-is.

## Interface contracts

- Upstream oh-my-zsh installer: flags are positional arguments, so the call needs
  the documented empty `$0` placeholder
  (`sh -c "$(curl ...)" "" --keep-zshrc --unattended`). Without it the flags are
  swallowed as `$0`. The flags mean: keep an existing `.zshrc`; do not change the
  login shell; do not run zsh; do not ask before overwriting.
- chezmoi: `apply` prompts when a target changed since it was last written
  ("If a target has been modified since chezmoi last wrote it then the user will
  be prompted if they want to overwrite the file"). `--force` means "Make all
  changes without prompting". The step label, argument order, and timing line
  format stay exactly as they are so `steps.sh` and any log parsing are unaffected.
- The functional test asserts observable calls/files only: recorded installer
  arguments, the skip output, and the literal apply step in `install.sh`. It does
  not call private helpers from the shell scripts.

## Evidence

Load-bearing claims verified before this plan:

- Base tip `d315ecd` (both `develop` and this branch); issue #82 is open, labels
  `bug`, milestone `v0.4.0 - reliability: honest verification`; no open PR or
  branch targets it; no pre-existing `specs/82*` folder.
- `setup/install.sh:158` — current apply step has no `--force`;
  `setup/development/oh-my-zsh/oh-my-zsh.sh:11` — current installer call has no
  flags. `setup/post-install.sh:42` runs that function.
- Local chezmoi `v2.72.2` in a temp HOME reproduced the failure verbatim:
  `.zshrc has changed since chezmoi last wrote it?` →
  `could not open a new TTY: open /dev/tty: no such device or address` → exit 1;
  rerun with `--force` → exit 0 and the file restored. `chezmoi apply --help`
  lists `--force` ("Make all changes without prompting").
- Upstream `ohmyzsh/ohmyzsh` `tools/install.sh` (read from source): `setup_zshrc()`
  returns early when `KEEP_ZSHRC=yes`, so no backup and no template; `--keep-zshrc`
  sets it; `--unattended` sets `RUNZSH=no`, `CHSH=no`, `OVERWRITE_CONFIRMATION=no`;
  the documented invocation includes the empty `$0`.
- Grep of `setup/` for `.zshrc` found no direct writes by repo scripts; the only
  rewriter is that upstream installer (bun.sh:127-129 deliberately generates
  completions without touching `.zshrc`). `reports/versions.sh:141,144` reads
  dotfile-derived state in both scripts, which rules out moving the apply step.
- `tests/AGENTS.md` requires stubbed external commands, per-test temp HOME, and
  assertions on observable behavior. `tests/test.sh:83-149` runs `bash -n`,
  source/guard checks, shellcheck, and every `*-test.sh` under `tests/`.

## Decisions

No MADR record is needed: this restores the repository's already-declared split
("declarative files → chezmoi, imperative actions → bash"; constitution axiom 1)
rather than introducing a new stack, protocol, install method, or workflow. The
rejected alternatives and their costs are recorded in `spec.md` Context.

## Verification

- `bash tests/setup/dotfiles-convergence-test.sh` — red first, then green; covers
  the installer flags, the installed-guard skip, and the apply-step contract.
- `bash -n` and shellcheck on the two changed setup scripts; then `./tests/test.sh`
  (full static + functional gate).
- `docker compose -f tests/compose.yml run --rm test` — isolated static check.
- `./tests/test.sh --vm --reuse` against a VM configured by an earlier run — the
  real rerun regression detector from #30; expect no TTY error, a printed versions
  report, and exit 0. Use `--keep` to inspect on failure.
- Manual walk of the five acceptance scenarios in `spec.md` before PR.

## Sequencing

1. Red: add `tests/setup/dotfiles-convergence-test.sh` with all three assertions;
   confirm it fails on the unmodified tree.
2. Green: add `--keep-zshrc --unattended` (with the empty `$0`) to
   `install_oh_my_zsh`; add `--force` to the `step chezmoi` line in `install.sh`.
3. Run the focused test, then the full gate, then the Docker check.
4. Multipass rerun e2e on an already-configured VM (`--reuse`, `--keep` on failure).
5. Self-review against the acceptance criteria; two atomic commits (test+fix can
   land together as one red-green pair if history prefers).

## Risks

- `--force` overwrites hand-edited managed dotfiles without asking. Intended: the
  repository is their declared owner, and this is the issue's expected behavior.
- `--unattended` stops the framework from changing the login shell; the repo
  already does this in `config_zsh` (`setup/install.sh:130`), so no capability is
  lost. Running `post-install.sh` alone was never a supported fresh-machine flow.
- On a machine with no `.zshrc` at all, upstream still writes its template even
  with `--keep-zshrc` (the flag only guards an existing file). Not a regression
  and outside the two-script flow.
- On the first rerun of an older machine, `--force` replaces the framework template
  with the curated file; the existing `.zshrc.pre-oh-my-zsh` backup stays, as
  decided.
- The empty `$0` in the installer call is easy to drop; the test asserts the
  recorded arguments so that mistake fails loudly.
