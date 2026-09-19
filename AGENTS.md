# ubuntu-config

Fresh-Ubuntu setup: bash scripts (`setup/`) + chezmoi dotfiles (`dotfiles/`). No lint, CI, or package manager. Scripts assume Ubuntu with `apt` + `sudo`. Humans: see `README.md`.

## Skills (load the one matching your task)

- Adding or extending a setup script (`install_*`/`config_*`, apt repos, version guards, wiring) → `install-package`.
- Running or iterating on tests (`./tests/test.sh`, docker-isolated, Multipass e2e, `--reuse` loop) → `run-tests`.
- Working with reports (`versions.sh`, `gaps.sh`, `chk`/`src` rows, baseline refresh) → `reports`.

## Rules

- Declarative files → chezmoi in `dotfiles/` (`dot_*` → `$HOME`, `*.tmpl` rendered with `~/.config/chezmoi/chezmoi.toml` data); imperative commands (`chsh`, `gsettings`, clones) → stay in bash.
- Public repo: never commit secrets. Root `.gitignore` (commit deny-list) and `dotfiles/.chezmoiignore` (deploy deny-list) must stay in sync when adding dotfiles.
- Atomic, conventional commits (`feat:`, `fix:`, `docs:`, `refactor:`, ...).
