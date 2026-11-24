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

# installing one app
bash setup/development/github-cli.sh repository
sudo apt update
bash setup/development/github-cli.sh install
bash setup/development/github-cli.sh version
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
- AnythingLLM Desktop (AppImage in `~/Applications`, verified against the sha256 GitHub publishes for the release asset, plus its AppArmor profile and launcher entry)
- GNOME browser connector + Deja Vu extension (window geometry memory)
- Handy speech-to-text (config only - install the AppImage manually, see below)

### Development

- Git, GitHub CLI, Docker (+ Compose, Sandboxes `sbx`), zsh (set as default shell) + config
- zoxide, uv, Ghostty (+ config + set as GNOME default terminal), Ollama, Homebrew
- pnpm (JS/TS packages; fnm remains the Node version manager), bun
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

## Language package managers

New setup scripts follow the [language package-manager policy](docs/language-package-managers.md): uv for Python (pip/pipx stay as agent-compatible fallbacks), fnm for Node versions, pnpm for JS/TS packages, and bun because the shell config references it. Other languages are decided when a script needs them.

## Failure handling

`install.sh` and `post-install.sh` run every step even if one fails, then
print a summary naming the failed steps and exit nonzero. Set `FAIL_FAST=1` to
stop at the first failing step instead:

```sh
FAIL_FAST=1 ./setup/install.sh
```

Credential sync is advisory: missing secrets are reported as pending in
non-interactive runs and never fail the run or count as a failed step.

## Manual steps

Some apps can't be installed programmatically. See [`setup/manual-installation.md`](setup/manual-installation.md) for the full list.

## Reports

### Versions

Report-only version table for everything the scripts manage. Installs nothing, always exits `0`:

```sh
./reports/versions.sh
multipass exec <vm-name> -- bash ubuntu-config/reports/versions.sh  # same, inside the e2e VM (see Testing)
```

### Gaps

Report-only list of host-installed apps not tracked by this repo (apt, snap, flatpak, AppImage). Installs nothing, always exits `0`. Builds the apt baseline from the vendored official desktop manifest, so it needs no network:

```sh
./reports/gaps.sh
```

Baseline: `reports/baselines/ubuntu-26.04.1-desktop-manifest.txt` (names from `https://releases.ubuntu.com/26.04/ubuntu-26.04.1-desktop-amd64.manifest`). See [Updating to a new Ubuntu version](#updating-to-a-new-ubuntu-version) to refresh it after a release bump.

## Security

See [integrity exceptions](docs/integrity-exceptions.md) for setup tools that
are intentionally retained without publisher-provided integrity material.

## Updating to a new Ubuntu version

When the repo moves to a newer Ubuntu release:

1. Bump the version pins: `UBUNTU_IMAGE` in `tests/test.sh`, the image in `tests/compose.yml` and `tests/Dockerfile`, and the tested-release note above. Both file changes trigger the `test-image` workflow to rebuild and publish the CI image.
2. Refresh the gaps baseline from the point-release desktop manifest (use the exact release, e.g. `26.04.1`):

   ```sh
   curl -sL https://releases.ubuntu.com/<release>/ubuntu-<release>-desktop-amd64.manifest \
     | awk '{print $1}' | sort -u > reports/baselines/ubuntu-<release>-desktop-manifest.txt
   ```

3. Update the baseline filename referenced in `reports/gaps.sh`.
4. Re-run `./tests/test.sh` and `./reports/gaps.sh` (expect near-empty on a fresh VM).

## Testing

Static checks are zero-dependency (shellcheck runs only if installed). The source-only check parses declarations without executing scripts:

```sh
./tests/test.sh
```

Python metadata parser unit tests use only Python's standard library and local fixtures (no network access):

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/python -v
```

Isolated static check in Docker (`ubuntu:26.04`, repo mounted read-only):

```sh
docker compose -f tests/compose.yml run --rm test
```

This local command always builds from `tests/Dockerfile`, so it is authoritative
when you change the toolchain image. CI instead pulls a prebuilt image from GHCR
so apt mirrors stay off the pull-request critical path; the `test-image` workflow
refreshes it nightly with a cache-free build and the full suite, which is where
broken apt repositories and changed toolchain packages surface. A PR that changes
`tests/Dockerfile` or `tests/compose.yml` builds locally instead, so a stale image
cannot hide a bad change. If the image cannot be pulled (before the first
publish or during a registry outage), CI warns and falls back to a local build.
One-time setup: make the `ubuntu-config-test` GHCR package public so fork PRs
can pull it without credentials.

Full e2e on a fresh Multipass VM (requires Multipass on host):

```sh
./tests/test.sh --vm              # fresh VM, non-interactive CHEZMOI_*, SKIP_UPGRADE=1
./tests/test.sh --vm --keep       # leave VM running on failure for inspection
./tests/test.sh --vm --reuse      # reuse existing VM for fast iterations
```

For a faster development loop, seed a kept VM once, then re-run only the setup
scripts you changed:

```sh
./tests/test.sh --vm --keep            # one full install, keep the VM
bash tests/dev-iter.sh seed            # remember the current setup scripts
# edit one or more scripts under setup/
bash tests/dev-iter.sh                 # apt update + changed installers only
./tests/test.sh --vm --reuse      # full check before a pull request
```

`dev-iter.sh` is a shortcut, not verification: it skips unchanged apps and does
not replace the full `--reuse` run. Its baseline is stored per VM under
`${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-config/` and advances after each
successful iteration.

Each `--vm` phase writes per-app spans, logs and a summary under
`E2E_OBSERVABILITY_DIR` (default
`${XDG_DATA_HOME:-$HOME/.local/share}/ubuntu-config/observability/<run-id>/`) and
prints `records:` and `log:` paths. Start the local stack to browse traces,
correlated logs and metrics in Grafana at `http://localhost:3000` (`admin`/`admin`):

```sh
docker compose -f tests/observability/compose.yml up -d
docker compose -f tests/observability/compose.yml down
```

The stack provisions an **E2E runs** dashboard and a few alert rules under
**E2E Observability**. The span list and record timing come from the replayed
records in Loki, so they are available even when the stack starts after a run;
the trace-metric panels fill in when it runs during the run. Alerts are for
local definition and evaluation only — no notification channel is configured.
The chosen feature scope is recorded in
[decision 0012](docs/decisions/0012-local-grafana-feature-scope.md). Ready-made
Explore queries and the trace-to-logs walkthrough are in the
[Grafana query cookbook](docs/runbooks/grafana-query-cookbook.md).

Live forwarding from the VM is best effort; an unreachable collector warns once
and the durable records remain complete.

The e2e VM is `ubuntu-config-test-<checkout-dir>-<base62>` (see [`tests/vm-name.sh`](tests/vm-name.sh)): the slug is the checkout directory name and the suffix is a base62 digest of its full path. Every checkout — including the original repository rather than a worktree — gets its own stable VM, so concurrent agents cannot overwrite each other. Each `--vm` run prints the name, and `--reuse`/`--keep` affect only that VM. Only one e2e run may use a given VM at a time: a second run against the same checkout exits immediately with an error naming the VM, without waiting or touching the VM. Runs against other worktrees remain independent.

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
  desktop-apps/         # chrome, spotify, obs, timeshift, fsearch, handy-config, gnome-extensions, ...
  development/          # git, GitHub CLI, docker, zsh, ghostty, opencode, ollama, fnm, ...
  helpers/              # shared shell helpers for setup scripts
  manual-installation.md
dotfiles/               # chezmoi source state (dot_* → $HOME, *.tmpl rendered)
.agents/skills/         # cross-agent skills (opencode, Cursor, VS Code, Codex, …)
reports/
  versions.sh           # report-only install report
  gaps.sh               # report-only host-vs-repo gaps (apt/snap/flatpak/AppImage)
  baselines/            # vendored Ubuntu desktop manifest baseline
tests/
  test.sh               # static + optional Multipass e2e
  compose.yml / Dockerfile
```

## Adding a new app

1. Add a single-purpose `setup/<area>/<name>.sh` defining one `install_*` / `config_*` function. Keep it rerun-safe (guard repeats, `groupadd -f`, overwrite apt sources). If the app needs extra apt packages, add a `<pkg>_dependencies()` function in the same file and call it from `install_<pkg>()` (see `setup/development/homebrew.sh`).
2. `source` it and append its call in `setup/install.sh` or `setup/post-install.sh`, plus a `chk`/`src` row in `reports/versions.sh`.
3. Config files → `dotfiles/` via chezmoi; commands → bash.

`tests/test.sh` enforces this contract fail-closed. For the full workflow (phases, install-method priority, apt-repo function, version guards, examples) the repo's `install-package` skill covers it.

## Installing one app

Package scripts expose a small command interface when run directly. The main
package uses one argument:

```sh
bash setup/development/github-cli.sh install
bash setup/development/github-cli.sh version
bash setup/development/docker.sh install
bash setup/development/docker.sh version
```

Scripts with additional components use `<component> <command>`:

```sh
bash setup/development/cursor.sh cli install
bash setup/development/cursor.sh cli version
bash setup/development/docker.sh compose version
```

The supported commands are `install`, `repository`, `config`, and `version`.
Scripts remain safe to `source`; dispatching only happens when a script is
executed directly. Scripts with multiple related functions expose components
using names such as `cli`, `compose`, or `plugins`.
