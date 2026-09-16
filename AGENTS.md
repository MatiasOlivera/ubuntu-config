# ubuntu-config

Fresh-Ubuntu setup via bash scripts. No tests, lint, CI, or package manager.

## Conventions

- Use conventional commits
- Each app script under `essentials/`, `desktop-apps/`, `development/` exposes one `install_*` / `config_*` / `configure_*` function; `install.sh` and `post-install.sh` only `source` scripts and call those functions — never inline install logic in the entrypoints.
- Reusable `configure_*` functions must also work standalone: guard with `if [[ ${BASH_SOURCE[0]} == "$0" ]]; then ... fi` (see `development/git/git-config.sh`).
- Verify shell edits with `bash -n <file>` (no test suite exists).

## Structure

- `install.sh` (requires `--name "..." --email "..."`, both mandatory) runs essentials → desktop-apps → development. Add new steps by sourcing the script and appending the call in the matching section.
- `post-install.sh` runs after it (oh-my-zsh, fnm, antigravity) and assumes `install.sh` already provided zsh/curl.
- `README.md`'s `./git-config.sh` path is stale; the script lives at `development/git/git-config.sh`.

## Gotchas

- Scripts assume Ubuntu with `apt` + `sudo`. `docker.sh` is rerun-safe (guards group/user, overwrites its apt source file); keep new scripts single-purpose and guard any step that fails when repeated.
- Match the surrounding file's indentation when editing (tabs vs spaces varies by file).
