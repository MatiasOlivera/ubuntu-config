# ubuntu-config

Fresh-Ubuntu setup: bash scripts (`setup/`) + chezmoi dotfiles (`dotfiles/`). Scripts assume Ubuntu with `apt` + `sudo`. Humans: see `README.md` (commands, reports, project structure).

## Skills (load the one matching your task)

Skills live in `.agents/skills/` (cross-agent: opencode, Cursor, VS Code, Codex, ...).

- Adding or extending a setup script (`install_*`/`config_*`, apt repos, version guards, wiring) → `install-package`.
- Adding or changing a chezmoi dotfile (`dotfiles/`, `dot_*` → `$HOME`, `.tmpl` data, deny-list sync) → `add-dotfile`.
- Running or iterating on tests (scoped checks, full gate, Docker, Multipass) → `run-tests`.
- Working with reports (`versions.sh`, `gaps.sh`, `chk`/`src` rows, baseline refresh) → `reports`.

## Commands

Test commands — scoped checks, full gate, Docker and Multipass — live in the `run-tests` skill. Load it before running or iterating on tests.

Anything beyond verify (adding apps, reports, baselines): `README.md` ("Testing", "Reports").

## Rules

- Declarative files → chezmoi in `dotfiles/` (`dot_*` → `$HOME`, `*.tmpl` rendered with `~/.config/chezmoi/chezmoi.toml` data); imperative commands (`chsh`, `gsettings`, clones) → stay in bash.
- Public repo: never commit secrets. Root `.gitignore` (commit deny-list) and `dotfiles/.chezmoiignore` (deploy deny-list) must stay in sync when adding dotfiles.
- Setup scripts stay rerun-safe and source-only. The host `tests/test.sh` check sources library scripts, so run it only on trusted checkouts.

## Execution environment

MUST NOT run system-mutating `setup/` scripts (`install.sh`, `post-install.sh`, app install/config scripts) on the host machine: run them in Docker or Multipass instead. `tests/test.sh` and `reports/versions.sh` source library scripts, so run them only on trusted checkouts — for untrusted changes use `docker compose -f tests/compose.yml run --rm test` (the Multipass loop runs host-side checks before entering the VM, so it is trusted-checkout-only as well). `bash -n`, shellcheck, the grep-based contract checks, and `reports/gaps.sh` do not execute repo code and are host-safe on any checkout.

The root `opencode.json` adds command denials for setup scripts and selected host-mutating commands (`sudo`, `apt`, `apt-get`, `snap`, `chsh`). It is a command filter, not an OS sandbox; use Docker or Multipass for system-mutating work.

## For changes

- Run focused checks on the changed files while implementing.
- Run the full gate (see `run-tests`) before the first local review, stopping at the first failure.
- Rerun the full gate before the pull request only when review feedback changed code.
- When a change invalidates agent-facing docs (`AGENTS.md`, `.agents/skills/`), update them in the same PR.

## Version control

- Use atomic Conventional Commits
- Split commits by semantic concern; each commit must be independently revertable.
  Group only what cannot land separately.
- Explain the why in the body whenever a commit needs justification: bug fixes
  (symptom + root cause + why this fix), refactors, renames, sequencing changes.
  2–4 sentences. Omit the how - the diff shows it.
- Use Git flow for branches off `develop`: `<type>/<[issue-]slug>` matching
  the change's commit type (e.g. `fix/42-repo-key-missing`); release only as
  `develop` → `main`. `slug` = kebab-case title: lowercase, non-alphanumerics
  → `-`, capped at ~5 words / 60 chars.
- Never commit without explicit approval

## Docs

README.md and docs are for humans; AGENTS.md and skills are for coding agents

## Decisions

Non-trivial choices (stack, protocol, workflow) MUST be recorded as MADR records
in `docs/decisions/` (`NNNN-slug.md`); overturns note "supersedes `NNNN-…`" in
prose. Load the `adr` skill for the template and numbering when available.
