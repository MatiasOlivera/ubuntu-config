# ubuntu-config

Fresh-Ubuntu setup: bash scripts (`setup/`) + chezmoi dotfiles (`dotfiles/`). No lint, CI, or package manager. Scripts assume Ubuntu with `apt` + `sudo`.

## New setup script contract (enforced by `tests/test.sh`)

- Single-purpose script defining one `install_*`/`config_*` function. Plain `install_*` scripts need no guard; `*config*.sh` must run standalone via `if [[ ${BASH_SOURCE[0]} == "$0" ]]; then ... fi` (see `setup/development/zsh/zsh-config.sh`).
- Wire it up: `source` it and append its call in `setup/install.sh` (essentials → desktop-apps → development, then chezmoi apply) or `setup/post-install.sh` (oh-my-zsh, fnm, antigravity; assumes `install.sh` already provided zsh/curl). `test.sh` fails any library script not referenced by basename in one of them.
- Keep it rerun-safe (guard repeated runs, `groupadd -f`, overwrite apt sources — see `setup/development/docker.sh`).
- Declarative files → chezmoi in `dotfiles/` (`dot_*` → `$HOME`, `*.tmpl` rendered with `~/.config/chezmoi/chezmoi.toml` data); imperative commands (`chsh`, `gsettings`, clones) → stay in bash.
- Match the surrounding file's indentation (tabs vs spaces varies by file).

## Commands

- `install.sh` takes no args; non-interactive identity via `CHEZMOI_NAME`/`CHEZMOI_EMAIL`, else it prompts once and stores `~/.config/chezmoi/chezmoi.toml`. Ends with `chezmoi apply --source dotfiles/` + `tests/verify.sh`.
- `SKIP_UPGRADE=1 bash setup/post-install.sh` skips `apt upgrade` (test VMs only; run full upgrade on real machines).
- Static check (host-safe, zero-dep): `./tests/test.sh` — `bash -n` + sourced + source-only + standalone-guard checks, shellcheck only if installed.
- Isolated static: `docker compose -f tests/compose.yml run --rm test` (image `ubuntu:26.04` + bash/shellcheck, repo mounted read-only).
- Full e2e (needs Multipass on host): `./tests/test.sh --vm` (fresh VM, non-interactive `CHEZMOI_*`, `SKIP_UPGRADE=1`); `--keep`/`--reuse` only valid with `--vm`.
- `tests/verify.sh` is report-only, always exits 0, installs nothing; excludes manually installed apps (see `setup/manual-installation.md`).

## Secrets

Public repo: never commit secrets. Root `.gitignore` (commit deny-list) and `dotfiles/.chezmoiignore` (deploy deny-list) must stay in sync when adding dotfiles.

## Commits

Atomic, conventional commits (`feat:`, `fix:`, `docs:`, `refactor:`, ...).
