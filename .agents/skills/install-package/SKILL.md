---
name: install-package
description: Use when installing a new package/tool in this repo (adding a setup/<...>.sh script) or extending an existing setup script — an apt repository source, a version guard, or a config_* script. Triggers on "add <app>", "install <tool>", "wire an apt repo for X", "version guard", "new setup script".
---

# Install a package

End-to-end workflow for adding a package/tool to this repo so `tests/test.sh` stays green. The contract below is enforced fail-closed by `tests/test.sh`; AGENTS.md summarizes it, this skill has the steps.

## 1. Pick phase and location

| Phase | Contents | File location |
|---|---|---|
| essentials | system basics (`make`, `curl`, `flatpak`, …) | `setup/essentials/` |
| repositories | apt sources/keys only, no installs | next to their package's script |
| desktop-apps | GUI apps, install + `config_*` | `setup/desktop-apps/` |
| development | dev tools, editors, shells | `setup/development/` |
| post-install | oh-my-zsh, fnm, antigravity (need zsh/curl from `install.sh`) | `setup/development/` |

Existing examples: `desktop-apps/fsearch.sh`, `development/git/git.sh`, `development/zsh/zsh-config.sh`.

## 2. Follow the script contract

- Single-purpose script defining one `install_<pkg>()` or `config_<pkg>()`.
- **Adding an apt source**: define `install_<pkg>_repository()` separately — sources/keys only, **no** `apt update`, no installs. Wired into the repositories phase so the single `apt update` in `install.sh` covers it. Overwrite the `.sources` file (never append) for rerun-safety (see `development/docker.sh`).
- **Heavy install**: define `<stem>_version()` — fast, exit 0 iff installed, exactly one output line — as the single source of truth. Gate the install step on it:
  ```bash
  install_<pkg>() {
      local installed_ver
      if installed_ver="$(<stem>_version 2>/dev/null)"; then
          printf 'skip: <pkg> already installed (%s)\n' "$installed_ver"
          return 0
      fi
      # ...install...
  }
  ```
  Never gate cheap state (`groupadd`/`usermod`/`gsettings`/`chsh`/`remote-add`/`ensurepath`, `chezmoi apply`, `versions.sh`, `apt update`, repo functions, node pin) — those run every time.
- **Rerun-safe**: guard repeated runs, `groupadd -f`, overwrite apt sources.
- **`config_*` scripts** must also run standalone:
  ```bash
  if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
      config_<pkg>
  fi
  ```
- Match the surrounding file's indentation (tabs vs spaces varies by file).

## 3. Wire it up — all three places

1. **`setup/install.sh`**: add `source "<dir>/<pkg>.sh"` next to its neighbors, then `step install_<pkg>` / `step config_<pkg>` in the correct phase. `install_<pkg>_repository` calls go in the repositories phase, **before** `step apt_update`. Post-install-category scripts go in `setup/post-install.sh` instead.
2. **`reports/versions.sh`**: add a `src <path>` line **and** a `chk "<label>" <pkg>_version` row. Missing either breaks the versions table.
3. **`README.md` structure tree**: only when a new category/script needs listing.

## 4. Verify

- `./tests/test.sh` — static, zero-dep (bash -n, sourced-by-basename, source-only fn, standalone guard, shellcheck if installed).
- For install-path changes, iterate with the VM loop: seed once `./tests/test.sh --vm --keep`, then `./tests/test.sh --vm --reuse` (idempotency guards skip installed packages).

## 5. Commit

Single atomic commit, conventional type (`feat:`, `docs:`, `refactor:`, …). Never commit secrets; keep `.gitignore` ⇄ `dotfiles/.chezmoiignore` in sync if dotfiles are involved.