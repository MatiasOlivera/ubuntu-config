# ubuntu-config

> Opinionated, rerun-safe setup for a fresh Ubuntu workstation: `apt` packages, Flatpak/Snap apps, dev tools, and chezmoi-managed dotfiles in two scripts.

## Requirements

- Fresh Ubuntu with `apt` + `sudo`
- `bash`
- Internet access

No other dependencies. `install.sh` bootstraps `chezmoi`, `curl`, `make`, etc. itself.

> [!NOTE]
> Tested against `ubuntu:26.04`. Other recent Ubuntu releases should work but are not covered by e2e tests.

## Quickstart

```sh
git clone https://github.com/MatiasOlivera/ubuntu-config ubuntu-config
cd ubuntu-config
./setup/install.sh
./setup/post-install.sh
```

On first run `install.sh` asks once for your Git name/email (or set `CHEZMOI_NAME` / `CHEZMOI_EMAIL` for non-interactive runs). Values are stored in `~/.config/chezmoi/chezmoi.toml` so re-runs never prompt again.

```sh
CHEZMOI_NAME="Ada Lovelace" CHEZMOI_EMAIL="ada@example.com" ./setup/install.sh
```

```sh
bash setup/post-install.sh  # real machine: full apt upgrade
```

## What it does

`setup/install.sh` runs essentials → desktop apps → development, then applies dotfiles and prints a versions report. `setup/post-install.sh` finishes interactive shell setup (oh-my-zsh, fnm, AI CLIs).

### Essentials

- `make`, `curl`, `chezmoi`, `flatpak`, `pulseaudio-utils`, `libfuse2t64`, `synaptic`
- `pip`, `pipx` (Python tooling)

### Desktop apps

- Timeshift (system snapshots), FSearch, Google Chrome, OBS Studio (+ plugins), Spotify
- Handy speech-to-text (config only - install the AppImage manually, see below)

### Development

- Git, Docker (+ Compose), zsh (set as default shell) + config
- zoxide, Ghostty (+ config + set as GNOME default terminal), Ollama
- Cursor CLI, Postman, Beekeeper Studio, opencode
- oh-my-zsh + `zsh-autosuggestions` + `zsh-syntax-highlighting` + Powerlevel10k theme (`post-install.sh`)
- `fnm` + Node LTS (`post-install.sh`), Antigravity CLI (`post-install.sh`)

## Dotfiles

`dotfiles/` is a chezmoi source state, applied with:

```sh
chezmoi apply --source dotfiles/
```

Mapping:

| Source                  | Destination                                                   |
| ----------------------- | ------------------------------------------------------------- |
| `dot_zshrc`             | `~/.zshrc`                                                    |
| `dot_gitconfig.tmpl`    | `~/.gitconfig` (rendered with name/email from `chezmoi.toml`) |
| `dot_p10k.zsh`          | `~/.p10k.zsh`                                                 |
| `dot_config/ghostty/*`  | `~/.config/ghostty/*`                                         |
| `dot_config/opencode/*` | `~/.config/opencode/*`                                        |

> [!WARNING]
> This repo is public. Never commit secrets. Root `.gitignore` (commit deny-list) and `dotfiles/.chezmoiignore` (deploy deny-list) already block SSH/GPG keys, cloud credentials, tokens, and shell history - keep them in sync when adding new dotfiles.

Rule of thumb:

- Declarative files → chezmoi in `dotfiles/`
- Imperative actions (`chsh`, `gsettings`, clones) → bash in `setup/`

## Manual steps

Some apps can't be installed programmatically. See [`setup/manual-installation.md`](setup/manual-installation.md) for the full list.

## Reports

### Versions

Report-only version table for everything the scripts manage. Installs nothing, always exits `0`:

```sh
./reports/versions.sh
multipass exec ubuntu-config-test -- bash ubuntu-config/reports/versions.sh  # same, inside the e2e VM
```

### Gaps

Report-only list of host-installed apps not tracked by this repo (apt, snap, flatpak, AppImage). Installs nothing, always exits `0`. Builds the apt baseline from the vendored official desktop manifest, so it needs no network:

```sh
./reports/gaps.sh
```

Baseline: `reports/baselines/ubuntu-26.04.1-desktop-manifest.txt` (names from `https://releases.ubuntu.com/26.04/ubuntu-26.04.1-desktop-amd64.manifest`). See [Updating to a new Ubuntu version](#updating-to-a-new-ubuntu-version) to refresh it after a release bump.

## Updating to a new Ubuntu version

When the repo moves to a newer Ubuntu release:

1. Bump the version pins: `UBUNTU_IMAGE` in `tests/test.sh`, the image in `tests/compose.yml` and `tests/Dockerfile`, and the tested-release note above.
2. Refresh the gaps baseline from the point-release desktop manifest (use the exact release, e.g. `26.04.1`):

   ```sh
   curl -sL https://releases.ubuntu.com/<release>/ubuntu-<release>-desktop-amd64.manifest \
     | awk '{print $1}' | sort -u > reports/baselines/ubuntu-<release>-desktop-manifest.txt
   ```

3. Update the baseline filename referenced in `reports/gaps.sh`.
4. Re-run `./tests/test.sh` and `./reports/gaps.sh` (expect near-empty on a fresh VM).

## Testing

Static checks are host-safe and zero-dependency (shellcheck runs only if installed):

```sh
./tests/test.sh
```

Isolated static check in Docker (`ubuntu:26.04`, repo mounted read-only):

```sh
docker compose -f tests/compose.yml run --rm test
```

Full e2e on a fresh Multipass VM (requires Multipass on host):

```sh
./tests/test.sh --vm              # fresh VM, non-interactive CHEZMOI_*, SKIP_UPGRADE=1
./tests/test.sh --vm --keep       # leave VM running on failure for inspection
./tests/test.sh --vm --reuse      # reuse existing VM for fast iterations
```

`tests/test.sh` enforces the script contract: `bash -n` syntax, every library script sourced by `install.sh`/`post-install.sh`, source-only `install_*`/`config_*` functions, standalone `BASH_SOURCE` guard on every `*config*.sh`, plus shellcheck when available.

The e2e run sets `SKIP_UPGRADE=1` when calling `post-install.sh` inside the VM, skipping `apt upgrade` for speed. Run `post-install.sh` without it on a real machine for the full update.

```sh
SKIP_UPGRADE=1 bash setup/post-install.sh  # test VMs only: skip apt upgrade for speed
```

## Project structure

```text
setup/
  install.sh            # essentials → desktop-apps → development, then chezmoi apply + report
  post-install.sh       # oh-my-zsh, fnm/node, antigravity (needs zsh/curl from install.sh)
  essentials/           # make, curl, chezmoi, flatpak, fuse, pip/pipx, ...
  desktop-apps/         # chrome, spotify, obs, timeshift, fsearch, handy-config, ...
  development/          # git, docker, zsh, ghostty, opencode, ollama, fnm, ...
  manual-installation.md
dotfiles/               # chezmoi source state (dot_* → $HOME, *.tmpl rendered)
.opencode/skills/       # agent skills (install-package, run-tests, reports)
reports/
  versions.sh           # report-only install report
  gaps.sh               # report-only host-vs-repo gaps (apt/snap/flatpak/AppImage)
  baselines/            # vendored Ubuntu desktop manifest baseline
tests/
  test.sh               # static + optional Multipass e2e
  compose.yml / Dockerfile
```

## Adding a new app

1. Add a single-purpose `setup/<area>/<name>.sh` defining one `install_*` / `config_*` function. Keep it rerun-safe (guard repeats, `groupadd -f`, overwrite apt sources).
2. `source` it and append its call in `setup/install.sh` or `setup/post-install.sh`, plus a `chk`/`src` row in `reports/versions.sh`.
3. Config files → `dotfiles/` via chezmoi; commands → bash.

`tests/test.sh` enforces this contract fail-closed. For the full workflow (phases, apt-repo function, version guards, examples) the repo's `install-package` skill covers it.
