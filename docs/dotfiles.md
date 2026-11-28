# Dotfiles

`dotfiles/` is a chezmoi source state: `dot_*` files map to `$HOME`, and `*.tmpl`
files are rendered from `~/.config/chezmoi/chezmoi.toml`. Apply it with
`chezmoi apply --source dotfiles/`; `setup/install.sh` does this as part of setup.

## Secrets

This repo is public. Never commit secrets. The root `.gitignore` (commit deny-list)
and `dotfiles/.chezmoiignore` (deploy deny-list) already block SSH/GPG keys, cloud
credentials, tokens and shell history — keep them in sync when adding new dotfiles.

## Local edits

Chezmoi replaces a managed file with its source contents on apply. If you add an
entry locally to a managed config, copy it into the matching `dotfiles/` source
before the next apply or it will be removed.
