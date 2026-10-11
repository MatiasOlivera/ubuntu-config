# ubuntu-config

Fresh-Ubuntu setup: bash scripts (`setup/`) + chezmoi dotfiles (`dotfiles/`). No lint, CI, or package manager. Scripts assume Ubuntu with `apt` + `sudo`. Humans: see `README.md`.

## Skills (load the one matching your task)

Skills live in `.agents/skills/` (cross-agent: opencode, Cursor, VS Code, Codex, ...).

- Adding or extending a setup script (`install_*`/`config_*`, apt repos, version guards, wiring) → `install-package`.
- Adding or changing a chezmoi dotfile (`dotfiles/`, `dot_*` → `$HOME`, `.tmpl` data, deny-list sync) → `add-dotfile`.
- Running or iterating on tests (`./tests/test.sh`, docker-isolated, Multipass e2e, `--reuse` loop) → `run-tests`.
- Working with reports (`versions.sh`, `gaps.sh`, `chk`/`src` rows, baseline refresh) → `reports`.

## Rules

- Declarative files → chezmoi in `dotfiles/` (`dot_*` → `$HOME`, `*.tmpl` rendered with `~/.config/chezmoi/chezmoi.toml` data); imperative commands (`chsh`, `gsettings`, clones) → stay in bash.
- Public repo: never commit secrets. Root `.gitignore` (commit deny-list) and `dotfiles/.chezmoiignore` (deploy deny-list) must stay in sync when adding dotfiles.

## Version control

- Use atomic Conventional Commits; ≤72 chars
- Explain the why in the body whenever a commit needs justification: bug fixes
  (symptom + root cause + why this fix), refactors, renames, sequencing changes.
  2–4 sentences. Omit the how - the diff shows it.
- Use Git flow for branches
- Never commit without explicit approval

## Docs

README.md and docs are for humans; AGENTS.md and skills are for coding agents

## Decisions

Non-trivial choices (stack, protocol, workflow) MUST be recorded as MADR records
in `docs/decisions/` (`NNNN-slug.md`); overturns note "supersedes `NNNN-…`" in
prose. Load the `adr` skill for the template and numbering when available.