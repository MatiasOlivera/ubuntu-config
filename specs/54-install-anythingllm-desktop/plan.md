# plan.md - `54-install-anythingllm-desktop`

## Architecture

One new script plus three wiring edits. Nothing else in the install pipeline
changes: `setup/install.sh` sources and steps it (`:51`, `:114`, desktop-apps
phase after obsidian), `reports/versions.sh` gains a `src`/`chk` pair (`:49`,
`:98`), `reports/gaps.sh` classifies the artifact as managed, and
`README.md` lists the app.

Install flow:

```
install_anythingllm
  ├─ skip guard anythingllm_version        — artifact + readable marker, no network
  │     └─ present  → printf 'skip: …'
  │     └─ absent   → anythingllm_install_appimage (return 1 aborts the step)
  ├─ anythingllm_apparmor_profile          — cheap state, runs every invocation
  └─ anythingllm_desktop_entry             — cheap state, runs every invocation

anythingllm_install_appimage
  ├─ uname -m → asset ∈ {AnythingLLMDesktop.AppImage, AnythingLLMDesktop-Arm64.AppImage}
  ├─ one GET releases/latest → "<tag>\t<sha256>" (anythingllm_release_meta)
  ├─ GET releases/download/<tag>/<asset> → $dir/AnythingLLMDesktop.AppImage.part
  ├─ sha256sum --check (digest vs .part) — mismatch → rm .part, fail
  ├─ chmod +x; atomic same-directory mv
  └─ write version marker LAST (${tag#v})
```

Design properties:

- No remote bytes are ever parsed as shell. The only artifact that lands is the
  AppImage that passed `sha256sum --check` against the digest GitHub publishes
  for that release asset. Engine bundles are deliberately not fetched.
- Tag and digest come from one API response, so a release published mid-run
  cannot pair a `latest` tag with another release's digest.
- Fail-closed everywhere on the install path: missing `curl`/`python3`, absent
  asset, non-`sha256` or empty digest, transport error, and mismatch each print
  `error: anythingllm: …` on stderr, remove the `.part`, and return 1. The
  marker is written last, so a step that failed cannot claim to be installed.
- The marker is what makes reruns network-free: an AppImage cannot be read for a
  version cheaply and running it needs a display, so the guard is a file-and-
  marker test. A missing artifact still reinstalls despite a stale marker.
- Cheap idempotent state is never gated on the guard and never overwrites:
  an existing profile or `.desktop` file belongs to the user (their machine may
  have run the vendor installer). AppArmor degrades to `skip:`/`warn:` because
  a non-AppArmor host is a supported configuration, not a failure.
- No EXIT trap is set: `setup/install.sh` owns the process trap for the sudo
  keepalive, and `step` containment must stay intact.

## Data models

Two files, both outside version control:

- `$ANYTHINGLLM_INSTALL_DIR/AnythingLLMDesktop.AppImage`
  (`ANYTHING_LLM_INSTALL_DIR` knob, default `$HOME/Applications`) — the verified
  artifact, always named `AnythingLLMDesktop.AppImage` regardless of the asset
  that supplied it.
- `${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-config/anythingllm.version` —
  one line, the installed tag with the leading `v` stripped; the single source of
  truth for `anythingllm_version`. An empty marker is not a version (`grep .`).

Wire format consumed (read-only):

- `$HOME/.local/share/applications/anythingllmdesktop.desktop` — INI keys taken
  from upstream's installer so a hand edit stays recognizable, except `Exec`,
  which this script quotes: the desktop-entry spec requires quoting any argument
  outside its safe character set (a space in the install dir would otherwise end
  the executable name), and escapes `\`, `"`, `$` and backtick inside.
- `/etc/apparmor.d/anythingllmdesktop` — profile text chosen by
  `apparmor_parser --version` major (≥4: `abi <abi/4.0>,` + `userns,`; else
  classic `#include`). Path pattern `/**/AnythingLLMDesktop.AppImage` keeps the
  profile valid if the artifact moves.

## API contracts

Publisher contract (outbound, GitHub REST):

- `GET https://api.github.com/repos/Mintplex-Labs/anything-llm/releases/latest`
  with `Accept: application/vnd.github+json`, `curl -fsSL --retry 3` — one
  response supplies `tag_name` and the arch-matched asset's `digest`
  (`"sha256:<64-hex>"`, readable unauthenticated; 60 req/hr anonymous is ample
  for a guard that never fires on reruns).
- `GET https://github.com/Mintplex-Labs/anything-llm/releases/download/<tag>/<asset>`
  — the CDN-backed asset for the tag just resolved.
- Host prerequisites: `curl`, `python3` (stdlib `json` only), `sha256sum`, `sed`,
  `uname`, `sudo` (only when writing the AppArmor profile). `python3` absence
  fails the step closed rather than installing unverified bytes.

Repo contract (inbound, per AGENTS.md / `install-package` skill):

- Defines `install_anythingllm` and `anythingllm_version`; helpers are named
  `anythingllm_*`, which matches no dispatcher pattern (`install_*`/`config_*`/
  `*_version`), so they cannot be routed to as phantom `<component> <command>`
  targets and `tests/test.sh` stays green on the source-only checks.
- Standalone interface: `bash setup/desktop-apps/anythingllm.sh install|version`.
- stdout markers: `skip: anythingllm already installed (<ver>)`,
  `skip: apparmor not detected (…)`, `warn: apparmor_parser missing; …`,
  `warn: profile written but not loaded: …`
- stderr markers: `error: anythingllm: unsupported architecture: <arch>`,
  `error: anythingllm: no published sha256 for <asset>`,
  `error: anythingllm: download failed for <asset> (<tag>)`,
  `error: anythingllm: sha256 mismatch for <asset> (<tag>)`.

Test contract: `tests/setup/desktop-apps/anythingllm-test.sh` is hermetic,
modeled on `gnome-extensions/deja-vu-test.sh` — `ANYTHINGLLM_SRC` override,
sandboxed `HOME`/`TMPDIR` with the installer's own knobs
(`ANYTHING_LLM_INSTALL_DIR`, `XDG_STATE_HOME`) pinned inside it, so a developer
who exports them cannot have the suite write the fake payload over their real
install, closed PATH (`$T/bin` stubs for `curl`/`sudo`/`apparmor_parser`/`uname`,
`$T/sysbin` coreutils symlinks), a `python3`-generated release-JSON fixture with
a decoy asset, and a tiny real fixture whose `sha256sum` is computed for real.
Assertions are black-box: exit codes, stdout/stderr markers, filesystem state.
Scenario coverage maps 1:1 to the spec, including the spaced install dir
asserted on the quoted `Exec` value. Picked up automatically by `tests/test.sh`
(`find tests -name '*-test.sh'`), no registration.

## Sequencing

1. ADR `0005-anythingllm-desktop-integrity` — records the integrity source chosen
   in the spec phase (issue #54 defines intent only; the how is decided here).
2. Functional test (red): fresh-install, digest-mismatch, null-digest,
   absent-asset, arm64 and marker scenarios all fail against the empty repo.
3. `setup/desktop-apps/anythingllm.sh` (green) + wiring in `install.sh`,
   `versions.sh`, `README.md`.
4. `reports/gaps.sh` fixes so the managed AppImage stops reporting as a gap:
   candidates reduced to basenames line-wise (`xargs -n1` split paths on
   spaces), and `Exec` parsing that keeps a quoted path whole — quoting `Exec`
   in step 3 makes the old `s/ .*$//` cut produce a bogus candidate.
5. Verify chain per AGENTS.md: static → docker-isolated → Multipass e2e.
6. PR onto `develop`; commits split by concern — feat (script, wiring, test),
   fix (gaps.sh), docs (ADR + specs/), then the review fixes as their own
   revertable commits.

## Decisions

- `docs/decisions/0005-anythingllm-desktop-integrity.md` — verify the release
  asset against the `sha256` digest GitHub publishes, instead of the four
  alternatives: executing the vendor `installer.sh` (forbidden by ADR 0003,
  interactive at a variable number of prompts, ~2 GB of unrequested engines);
  CDN `/latest/` with no check plus an exception record; a self-authored
  `sha256` pin in the script (TOFU plus per-release re-audit); waiting for vendor
  checksums (the vendor publishes none — `.sha256`, `.zsync`, `checksums.txt`
  under `/latest/` all 404).
  Residual risk accepted: the digest is computed by GitHub at upload, so the
  attester is also the host; ADR 0003 already bounds the goal to removing
  unverifiable execution, not full supply-chain security.
- Version reported from an install-time marker, not the artifact — the AppImage
  has to be executed (and needs a display) to answer. Consequence: the guard
  never upgrades an existing install; convergence to a newer release is manual.
- Install location `$HOME/Applications` (upstream's own default, overridable with
  `ANYTHING_LLM_INSTALL_DIR`) rather than `/opt`, so the step needs no root for
  the artifact itself.

## Risks

- GitHub renames or drops `assets[].digest` → installs fail closed with a named
  error; repair = update the contract, not weaken the check. Reruns of an
  already-installed machine are unaffected (the guard never reaches the network).
- Vendor renames a release asset → same loud failure; the absent-asset scenario
  pins that behavior.
- A machine that already ran the vendor installer keeps a second artifact in
  `$HOME`; convergence is manual (delete the old artifact and launcher entry,
  re-run). Deliberately not automated: deleting user files is out of scope.
- `python3` on a stripped host → fail-closed install, no unverified bytes.
- Rollback: revert three commits; the only persisted state is inside `$HOME`
  (plus an optional `/etc/apparmor.d/anythingllmdesktop`), so removing the
  AppImage, marker and `.desktop` file cleans up completely.
- VM e2e pays the same ~905 MB artifact download as a real machine.

## Assumptions

All load-bearing facts verified against live sources on 2026-11-04; no open
assumptions remain.

- `releases/latest` exposes `assets[].digest` unauthenticated: `v1.19.0` reports
  `AnythingLLMDesktop.AppImage` at 905441828 bytes with
  `sha256:8b407abafa281e5f2b58af04399011784894a5a0414fb58eb32062dad6cc8ef2`, the
  size the vendor CDN also reports for `/latest/`. Evidence: `curl` of the REST
  endpoint plus `curl -sIL` on the CDN asset.
- No publisher checksum material exists: v1.19.0 lists seven assets, none a
  checksum file; `/latest/{AnythingLLMDesktop.AppImage.sha256,.zsync,checksums.txt}`
  return 404. Evidence: asset list and the probes.
- No apt/`.deb`/Flatpak distribution: Flathub's appstream API has no
  `com.mintplexlabs.*` app. Evidence: appstream query.
- Upstream `installer.sh` (532 lines, POSIX `set -eu`) prompts with `read -p` at
  a state-dependent count, writes the profile with syntax chosen by
  `apparmor_parser --version`, uses the `/**/AnythingLLMDesktop.AppImage` pattern
  and the `.desktop` keys copied here, and pulls lemond/llama.cpp/ollama bundles
  (~2 GB). Evidence: the script fetched from the CDN, plus the release asset list.
- `libfuse2t64` (needed to run an AppImage) is installed earlier in the same run
  by `setup/essentials/fuse.sh`; `python3` is in the vendored desktop baseline
  manifest and in `tests/Dockerfile`. Evidence: those files.
