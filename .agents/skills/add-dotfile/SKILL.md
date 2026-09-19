---
name: add-dotfile
description: Use when adding or changing a dotfile managed by chezmoi in this repo (dotfiles/) — a new dot_* file, a .tmpl rendered from chezmoi.toml data, moving a config file into dotfiles, or keeping the .gitignore⇄.chezmoiignore deny-lists in sync. Triggers on "add a dotfile", "chezmoi", "move <file> to dotfiles", ".tmpl", ".gitconfig", ".zshrc".
---

# Add or change a dotfile

`dotfiles/` is a chezmoi source state applied with `chezmoi apply --source dotfiles/` (run by `setup/install.sh` at the end).

## 1. Naming — source maps to destination

| Source | Destination |
|---|---|
| `dot_zshrc` | `$HOME/.zshrc` |
| `dot_gitconfig.tmpl` | `$HOME/.gitconfig` (rendered) |
| `dot_p10k.zsh` | `$HOME/.p10k.zsh` |
| `dot_config/ghostty/config` | `$HOME/.config/ghostty/config` |
| `dot_config/opencode/opencode.json` | `$HOME/.config/opencode/opencode.json` |

`dot_` → `$HOME/`; `dot_config/<app>/…` → `~/.config/<app>/…`.

## 2. Template only what varies

Append `.tmpl` only when values are machine/user-dependent, rendered from `~/.config/chezmoi/chezmoi.toml` `[data]` (identity set by `install.sh`):

```
[user]
	name = {{ .name | quote }}
	email = {{ .email | quote }}
```

Static files stay plain (no `.tmpl`): `dot_zshrc`, `dot_p10k.zsh`.

## 3. Declarative vs imperative

Declarative file content → `dotfiles/`. Actions (`chsh`, `gsettings`, clones, `git config` writes) → bash in `setup/`. Reference the template data from a `config_*` script only if it must create the file, not for content chezmoi owns.

## 4. Secrets — deny-list sync

Public repo: never commit secrets. When adding a dotfile, verify it does not match a deny pattern, and if you add a new secret-equivalent pattern, add it to BOTH:

- root `.gitignore` — commit deny-list
- `dotfiles/.chezmoiignore` — deploy deny-list (patterns match destination paths, e.g. `.ssh/**`, not `dot_ssh`)

They must stay in sync. If the file is a credential at all, prefer not managing it.

## 5. Apply and verify

```sh
chezmoi apply --source dotfiles/
./tests/test.sh   # static checks
```

If the dotfile feeds a script's config (`git-config`, `zsh-default`, …), confirm the row renders in `reports/versions.sh`.