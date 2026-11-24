---
name: install-package
description: Use when installing a new package/tool in this repo (adding a setup/<...>.sh script) or extending an existing setup script — an apt repository source, a version guard, or a config_* script. Triggers on "add <app>", "install <tool>", "wire an apt repo for X", "version guard", "new setup script".
---

# Install a package

> [Architecture] Uses Template Method

End-to-end workflow for adding a package/tool to this repo so `tests/test.sh` stays green. The contract below is enforced fail-closed by `tests/test.sh`; AGENTS.md summarizes it, this skill has the steps.

## 1. Pick phase and location

| Phase | Contents | File location |
|---|---|---|
| essentials | system basics (`make`, `curl`, `flatpak`, …) | `setup/essentials/` |
| repositories | apt sources/keys only, no installs | next to their package's script |
| desktop-apps | GUI apps, install + `config_*` | `setup/desktop-apps/` |
| development | dev tools, editors, shells | `setup/development/` |
| post-install | oh-my-zsh, fnm, antigravity (need zsh/curl from `install.sh`) | `setup/development/` |

Keep package scripts flat when a directory would contain only one script.

Use a directory only when it groups multiple related scripts for one package,
such as installation or package components.

## 2. Pick the install method

Use the highest rung that actually exists for the tool, in this order:

1. **Ubuntu apt** — plain `apt install`, no extra source.
2. **Vendor apt repository** — GPG key + `.sources`, overwrite, never append;
   the repo function does not run `apt update`.
3. **Checksum-verified release artifact** — publisher checksum or signature
   covering the exact artifact.
4. **Homebrew** — CLI tools only when the vendor ships no higher rung.
5. **flatpak / flathub** — desktop apps only.
6. **snap** — only when the vendor ships nothing else.
7. **Raw vendor `.deb` via curl** — last resort; explain in the PR why no
   higher rung exists.

Integrity is a constraint on every rung, not a rung of its own: never execute
unverifiable remote code. `curl … | sh` is not an option; a tool that only has
such an installer needs an entry in the integrity exception register
(`docs/integrity-exceptions.md`) first.

Break ties by, in order: idempotent and non-interactive installs; a verifiable
source; updates through a path this repo actually runs; least privilege.
State the chosen rung in the PR Verification section when adding an
application.

## 3. Follow the script contract

- **Artifact integrity**: before adding or updating a setup artifact, inspect
  the maintainer's official distribution channels for checksums or signatures
  covering that exact artifact. Use usable maintainer-published material when
  available. If none is available, use the GitHub release asset SHA-256 digest
  when available. If neither source has usable material, fail closed and
  record an explicit exception decision; never accept unverified bytes or use
  a self-authored hash pin. Record the artifact/version, sources checked,
  material found, and the reason for any GitHub fallback in the issue or PR.
  See `0007-artifact-integrity-source-priority.md` in `docs/decisions/`.

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
- **System dependencies**: if the package needs apt packages beyond what other scripts already manage, define an imperative `<pkg>_dependencies()` in the same file and call it inside `install_<pkg>()` after the skip-guard (see `development/homebrew.sh`). Keeps the script self-contained — no separate essentials scripts for another package's private deps. `apt install` is idempotent, so this stays rerun-safe.
- **Rerun-safe**: guard repeated runs, `groupadd -f`, overwrite apt sources.
- **`config_*` scripts** must also run standalone:
  ```bash
  if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
      config_<pkg>
  fi
  ```
- Match the surrounding file's indentation (tabs vs spaces varies by file).

## 4. Wire it up — all three places

1. **`setup/install.sh`**: add `source "<dir>/<pkg>.sh"` next to its neighbors, then `step install_<pkg>` / `step config_<pkg>` in the correct phase. `install_<pkg>_repository` calls go in the repositories phase, **before** `step apt_update`. Post-install-category scripts go in `setup/post-install.sh` instead.
2. **`reports/versions.sh`**: add a `src <path>` line **and** a `chk "<label>" <pkg>_version` row. Missing either breaks the versions table.
3. **`README.md` structure tree**: only when a new category/script needs listing.

## 5. Verify

- `./tests/test.sh` — static, zero-dep (bash -n, sourced-by-basename, source-only fn, standalone guard, shellcheck if installed).
- For install-path changes, iterate with the VM loop: seed once `./tests/test.sh --vm --keep`, then `./tests/test.sh --vm --reuse` (idempotency guards skip installed packages).

## 6. Commit

Single atomic commit, conventional type (`feat:`, `docs:`, `refactor:`, …). Never commit secrets; keep `.gitignore` ⇄ `dotfiles/.chezmoiignore` in sync if dotfiles are involved.
