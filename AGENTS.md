# ubuntu-config

Fresh-Ubuntu setup via bash scripts. No lint, CI, or package manager.

## Conventions

- Use atomic and conventional commits
- Reusable `config_*` functions must also work standalone: guard with `if [[ ${BASH_SOURCE[0]} == "$0" ]]; then ... fi` (see `development/git/git-config.sh`).
- Never run `./test.sh` or `./verify.sh` on the host. Verify isolated-only:
  - Static: `docker compose run --rm test`
  - Verify: `docker compose run --rm test ./verify.sh`
  - Multipass e2e: `./test.sh --vm --keep`

## Structure

- `install.sh` (requires `--name "..." --email "..."`, both mandatory) runs essentials → development → desktop-apps. Add new steps by sourcing the script and appending the call in the matching section.
- `post-install.sh` runs after it (oh-my-zsh, fnm, antigravity) and assumes `install.sh` already provided zsh/curl.

## Gotchas

- Scripts assume Ubuntu with `apt` + `sudo`. `docker.sh` is rerun-safe (guards group/user, overwrites its apt source file); keep new scripts single-purpose and guard any step that fails when repeated.
- Match the surrounding file's indentation when editing (tabs vs spaces varies by file).
