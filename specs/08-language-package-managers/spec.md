# spec.md - `08-language-package-managers`

## Context

Issue: [#8](https://github.com/MatiasOlivera/ubuntu-config/issues/8)

The issue asks for one documented policy per language ecosystem so future setup
scripts do not each invent a manager choice. At the current base (`bdfaaf8`),
`setup/development/uv.sh` already installs a checksum-verified uv and
`setup/install.sh` runs it, but the older `setup/essentials/pip.sh` and
`pipx.sh` are still installed while no script calls either. `dotfiles/dot_zshrc`
carries bun completions and `BUN_INSTALL` exports while no script installs bun.

The policy decisions are:

- **Python:** uv is the default manager. pip and pipx stay installed because
  coding agents commonly call them by name and uv provides no `pip` command.
- **JavaScript/TypeScript:** fnm remains the Node version manager. pnpm is the
  default package manager and is installed by this issue. bun is also
  installed because the existing shell configuration references it.
- **Other languages:** policies for Rust, Go, and any future ecosystem are
  decided when a script first needs one.

The policy lives in a dedicated, updateable document (`docs/language-package-managers.md`),
with AGENTS.md and the README pointing at it.

## User stories

- As an agent adding a Python setup script, I want one stated default manager
  so I do not re-litigate pip vs uv each time.
- As a person running coding agents on Python projects, I want `pip` and `pipx`
  still available so agent commands that use those names keep working.
- As an agent adding a JS/TS setup script, I want a stated default package
  manager that keeps the existing fnm-managed Node runtime.
- As a person whose shell config references bun, I want bun actually installed
  so its completions and PATH entries work on a fresh machine.
- As a reviewer, I want the picks and rejected alternatives in one live policy
  document so later changes can trace and update them without hunting ADRs.
- As a person reading the README or AGENTS.md, I want the policy stated where
  I look for contributor rules.

## Acceptance criteria (BDD)

```gherkin
Scenario: Python default is discoverable
  Given a contributor is about to add a Python setup script
  When they read AGENTS.md and the README
  Then they find uv named as the default Python manager
  And they find that pip and pipx remain installed as compatibility fallbacks

Scenario: agent-facing pip commands still work
  Given a fresh setup run has completed
  When a coding agent runs `pip install` or `pipx install`
  Then both commands are available
  And neither command is removed or disabled by this change

Scenario: JavaScript defaults are discoverable
  Given a contributor is about to add a JS/TS setup script
  When they read AGENTS.md and the README
  Then they find fnm named as the Node version manager
  And they find pnpm named as the default package manager

Scenario: pnpm is installed by setup
  Given a fresh Ubuntu machine with no pnpm installed
  When the setup runs
  Then pnpm is installed from a verifiable source
  And the `pnpm` command is available on PATH
  And the versions report shows a pnpm row with its version

Scenario: bun installation makes the existing shell config live
  Given a fresh Ubuntu machine with no bun installed
  When the setup runs
  Then bun is installed from a publisher-checksummed release artifact
  And the `bun` command is available on PATH
  And the existing bun completions and BUN_INSTALL exports in dot_zshrc apply

Scenario: new managers skip and report correctly
  Given pnpm and bun are already installed
  When the setup steps or version checks run
  Then each reports its existing version without downloading
  And the versions report shows both rows with those versions

Scenario: verified installs fail closed
  Given a downloaded release artifact does not match its expected checksum
  When the pnpm or bun install step runs
  Then it exits non-zero with a named error
  And no partial or unverified binary is left installed

Scenario: live policy document records the picks and alternatives
  Given a maintainer reviews the repository documentation
  When they open the language package-manager policy document
  Then it records uv, pnpm, and bun with their rejected alternatives
  And it states that other language policies will be decided when needed
  And AGENTS.md and the README point to it
```

## Constraints

- [ ] Add pnpm and bun following the install-package contract: one
      source-only script per manager with an `install_*` guard and `*_version()`
      function, wired into `setup/install.sh` (source + step), plus `src`/`chk`
      rows in `reports/versions.sh` and README mentions.
- [ ] Verify each downloaded artifact against available publisher or release
      integrity material before installing; fail closed on missing or
      mismatched checksum, transport failure, or missing asset. Never execute a
      remote install script.
- [ ] Keep every existing install script source-only, rerun-safe, and wired
      through `setup/install.sh` or `setup/post-install.sh`.
- [ ] Keep pip.sh, pipx.sh, fnm, and the bun lines in `dot_zshrc` unchanged;
      this issue changes policy docs and adds two managers, not removals.
- [ ] Cover both new install paths with self-contained, network-stubbed
      `tests/setup/development/*-test.sh` suites per `tests/AGENTS.md`.
- [ ] Update AGENTS.md so policy-type decisions point to the live document
      instead of requiring a MADR for this policy.
- [ ] Verify with the repository chain: `./tests/test.sh`, the isolated Docker
      check, and `./tests/test.sh --vm --reuse` because the install path
      changes.
- [ ] Make no OS-level install-method decision; that belongs to issue #7.
- [ ] Out of scope: installing Oxc, Vite+, or Rust/Go tooling; dropping fnm;
      rewriting existing Python setup scripts.
