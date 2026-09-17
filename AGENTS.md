# ubuntu-config

Fresh-Ubuntu setup via bash scripts + chezmoi dotfiles. No lint, CI, or package manager.

## Conventions

- Use atomic and conventional commits
- Reusable `config_*` functions must also work standalone: guard with `if [[ ${BASH_SOURCE[0]} == "$0" ]]; then ... fi` (see `setup/development/zsh/zsh-config.sh`).
- Never run `./tests/test.sh` or `./tests/verify.sh` on the host. Verify isolated-only:
  - Static: `docker compose -f tests/compose.yml run --rm test`
  - Verify: `docker compose -f tests/compose.yml run --rm test ./tests/verify.sh`
  - Multipass e2e: `./tests/test.sh --vm --keep`
- Public repo: never commit secrets. Root `.gitignore` + `dotfiles/.chezmoiignore` deny-list keys/credentials/tokens; keep both in sync when adding dotfiles.

## Structure

- `setup/install.sh` (no args; prompts Git name/email once, `CHEZMOI_NAME`/`CHEZMOI_EMAIL` for non-interactive) runs essentials → development → desktop-apps, then `chezmoi apply --source dotfiles/`. Add new steps by sourcing the script and appending the call in the matching section.
- `setup/post-install.sh` runs after it (oh-my-zsh, fnm, antigravity) and assumes `install.sh` already provided zsh/curl.
- `dotfiles/` is the chezmoi source state (`dot_*` → `$HOME` dotfiles, `*.tmpl` rendered with `~/.config/chezmoi/chezmoi.toml` data). Files → chezmoi, imperative commands (`chsh`, `gsettings`, clones) → stay in bash.
- `tests/` holds `test.sh`, `verify.sh`, and the Docker test harness (`Dockerfile`, `compose.yml`, root build context).

## Gotchas

- Scripts assume Ubuntu with `apt` + `sudo`. `docker.sh` is rerun-safe (guards group/user, overwrites its apt source file); keep new scripts single-purpose and guard any step that fails when repeated.
- Match the surrounding file's indentation when editing (tabs vs spaces varies by file).
