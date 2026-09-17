# ubuntu-config

Set-up a fresh Ubuntu installation installing apps and some configs

Installation scripts are grouped by purpose under `setup/`:

- `setup/desktop-apps/` contains final user applications (not for development)
- `setup/development/` contains development tools such as Git and Docker
- `setup/essentials/` contains common Linux utilities.

Each application script exposes an install function that is sourced and called
by `setup/install.sh`.

Install Ubuntu packages and apply dotfiles:

```sh
./setup/install.sh
```

On first run it asks for Git name/email (or set `CHEZMOI_NAME` /
`CHEZMOI_EMAIL` for non-interactive runs) and stores them in
`~/.config/chezmoi/chezmoi.toml`, then applies `dotfiles/` via chezmoi.

## Dotfiles

`dotfiles/` is the chezmoi source state (`chezmoi apply --source dotfiles/`).
Files map to `$HOME`: `dot_zshrc` → `~/.zshrc`, `dot_gitconfig.tmpl` →
`~/.gitconfig`, `dot_config/*` → `~/.config/*`.

This repo is public: never commit secrets. Root `.gitignore` (commit
deny-list) and `dotfiles/.chezmoiignore` (deploy deny-list) block SSH/GPG
keys, cloud credentials, tokens, and history files by default.

## Testing

Its run on a `ubuntu:26.04` Docker image.

```sh
docker compose -f tests/compose.yml build
docker compose -f tests/compose.yml run --rm test              # static + source-only (fast, zero-dep, default)
./tests/test.sh --vm                                           # same, then Multipass fresh-Ubuntu e2e
./tests/test.sh --vm --keep                                    # same, but leave VM running on failure for inspection
./tests/test.sh --vm --reuse                                   # e2e on host: reuse existing VM (skip launch) for fast iterations
./tests/test.sh --vm --reuse --keep                            # same, and leave VM running afterwards
```

The e2e run sets `SKIP_UPGRADE=1` when calling `post-install.sh` inside the
VM, skipping `apt upgrade` for speed. Run `post-install.sh` without it on a
real machine for the full update.

## Verify

Report-only version table for everything `install.sh` / `post-install.sh` set up
(manually installed apps excluded, always exits 0):

```sh
./tests/verify.sh
multipass exec ubuntu-config-test -- bash ubuntu-config/tests/verify.sh  # same, inside the e2e VM
```
