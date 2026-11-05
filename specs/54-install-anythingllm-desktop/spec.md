# spec.md - `54-install-anythingllm-desktop`

## Context

Issue: #54

The intent recorded in the issue is local-first retrieval: index the documents
that already live on this machine and query them from a GUI, without shipping
the corpus to a cloud assistant.

AnythingLLM Desktop is distributed only as an AppImage. There is no apt
repository, no `.deb`, and no Flatpak — Flathub has no `com.mintplexlabs.*`
app (checked against the Flathub appstream API on 2026-11-04). The documented
Linux method is `https://cdn.anythingllm.com/latest/installer.sh`, which is
unusable as the setup path for three independent reasons:

- It executes a remote script with no integrity material, which constitution
  axiom 3 and `docs/decisions/0003-remote-installer-integrity.md` forbid.
- It is `set -eu` with `read -p` prompts whose number depends on on-disk state
  (existing artifact, existing AppArmor profile), so it cannot be driven
  non-interactively from `setup/install.sh`.
- Besides the ~905 MB artifact it unconditionally downloads local-model engine
  bundles (lemond, llama.cpp CPU/Vulkan/CUDA, sometimes ollama) totalling
  roughly 2 GB.

The vendor publishes no checksum material for the artifact: the `v1.19.0`
release lists seven assets and none is a checksum file, and
`AnythingLLMDesktop.AppImage.sha256`, `.zsync`, and `checksums.txt` under
`https://cdn.anythingllm.com/latest/` all return `404`. GitHub does publish a
`sha256` `digest` per release asset, readable without authentication.

Goal: install and make launchable a desktop app whose bytes setup can hold to
published integrity material, without re-opening the unverifiable-execution
surface that #44 and #45–#50 exist to close.

## User stories

- As a person running the setup on a fresh Ubuntu machine, I want AnythingLLM
  Desktop installed with its AppArmor profile and launcher entry, so that after
  one command I can open a GUI and query my own documents locally.
- As a person re-running the setup, I want the step to report a skip and touch
  no network, so that an already-installed app is neither re-downloaded nor
  silently upgraded.
- As a reviewer of this repo, I want the artifact verified before it lands and
  the check to fail closed, so that setup never installs bytes it cannot
  account for.
- As the owner of a machine where the vendor installer already ran, I want the
  script to leave my existing AppArmor profile and launcher entry alone, so
  that adopting this repo does not overwrite state I configured by hand.

## Acceptance criteria (BDD)

```gherkin
Scenario: verified fresh install
  Given AnythingLLM Desktop is not installed
  When the setup AnythingLLM step runs with access to the GitHub release API
  Then the arch-matched AppImage is installed and executable in ~/Applications
  And the installed bytes match the sha256 GitHub publishes for that release asset
  And a launcher entry exists whose quoted Exec argument names the installed
  artifact
  And the step reports the installed version

Scenario: install directory with a space still launches
  Given the install directory path contains a space
  When the setup AnythingLLM step runs
  Then the launcher entry's Exec value quotes the path as a single argument
  And the quoted value names the installed artifact

Scenario: already installed skips without network
  Given AnythingLLM Desktop is installed and the version guard reports a version
  When the setup AnythingLLM step runs
  Then the step reports it skipped the install
  And no download is attempted

Scenario: digest mismatch is rejected
  Given the delivered artifact does not match the published digest
  When the setup AnythingLLM step runs
  Then the step fails with a message naming the mismatch
  And no artifact is installed and no version marker is written
  And no partial download file is left behind

Scenario: missing digest is rejected
  Given the release metadata carries no sha256 digest for the artifact
  When the setup AnythingLLM step runs
  Then the step fails
  And nothing is installed

Scenario: artifact absent from the release is rejected
  Given the release does not list the artifact the step asks for
  When the setup AnythingLLM step runs
  Then the step fails
  And nothing is installed

Scenario: interrupted download is rejected
  Given the download fails (server error or truncated transfer)
  When the setup AnythingLLM step runs
  Then the step fails
  And nothing is installed and no partial file remains

Scenario: an installed artifact is never re-fetched on a dead network
  Given AnythingLLM Desktop is installed
  When the setup step runs without network access
  Then the step still succeeds, because the guard never reaches the network

Scenario: missing artifact reinstalls despite a stale marker
  Given the version marker exists but the AppImage has been removed
  When the setup AnythingLLM step runs
  Then the artifact is installed again

Scenario: empty marker is not a version
  Given the version marker exists but is empty
  When the version guard runs
  Then it reports not installed

Scenario: architecture selects the matching artifact
  Given the machine reports aarch64
  When the setup AnythingLLM step runs
  Then the arm64 release asset is the one requested and verified

Scenario: existing privileged configuration is never overwritten
  Given an AppArmor profile or launcher entry already exists on the machine
  When the setup AnythingLLM step runs
  Then neither file is rewritten
  And the step still succeeds

Scenario: apparmor-less host degrades quietly
  Given the host has no AppArmor security filesystem
  When the setup AnythingLLM step runs
  Then the step reports the profile as a skip and still succeeds

Scenario: unsupported machine
  Given the machine's CPU architecture has no published artifact
  When the setup AnythingLLM step runs
  Then the step fails with a message naming the architecture
  And nothing is installed

Scenario: failure is contained to its step
  Given the AnythingLLM verification fails for any reason
  When the full `setup/install.sh` run executes
  Then only the AnythingLLM step reports the failure
  And later setup steps still run
```

## Constraints

- [ ] Security: no remote install script is parsed or executed. Only a release
      artifact verified against published integrity material is installed, and
      only that artifact — engines are the app's own business.
- [ ] Security: verification is mandatory and fail-closed. Missing digest,
      absent asset, transport failure, and mismatch each abort the step with a
      named error and leave no partial file.
- [ ] Rerun-safe and source-only per AGENTS.md: sourcing defines functions and
      runs nothing; standalone execution keeps the dispatcher contract
      (`install`, `version`).
- [ ] Cheap idempotent state (AppArmor profile, launcher entry) runs on every
      invocation but never overwrites an existing file.
- [ ] Integration points: `setup/install.sh` step, `reports/versions.sh`
      `src`/`chk` rows, and `reports/gaps.sh` AppImage classification all keep
      working; the functional test is picked up by `./tests/test.sh` with no
      registration.
- [ ] Support matrix: `AnythingLLMDesktop.AppImage` (x86_64) and
      `AnythingLLMDesktop-Arm64.AppImage` (aarch64). The installed file is
      always named `AnythingLLMDesktop.AppImage`.
- [ ] Install location: `$HOME/Applications`, honoring upstream's documented
      `ANYTHING_LLM_INSTALL_DIR` knob.
- [ ] Version semantics: install the latest published release at run time; the
      tag is recorded once at install. The guard means an existing install is
      never silently upgraded.
- [ ] Out of scope: the vendor's engine bundles (~2 GB), an in-place update
      mechanism, other desktop apps, and upstream's KDE-on-Wayland `Exec`
      flags (this setup is GNOME).

## Assumptions

- GitHub keeps exposing `assets[].digest` in the releases API, unauthenticated.
  Source: verified live on 2026-11-04 against `releases/latest` (`v1.19.0`),
  which reports `AnythingLLMDesktop.AppImage` at 905441828 bytes with
  `sha256:8b407abafa281e5f2b58af04399011784894a5a0414fb58eb32062dad6cc8ef2` —
  the same size the vendor CDN reports for `/latest/`. Verification step: a
  missing or malformed digest fails closed, which the test asserts.
- The vendor keeps publishing both AppImage assets under stable names in every
  release. Source: v1.17.0 through v1.19.0 asset lists. Verification step: the
  "artifact absent from the release is rejected" scenario covers a rename.
- The AppImage runs with `libfuse2t64`, installed by
  `setup/essentials/fuse.sh` in the earlier essentials phase.
- `python3` exists for release-metadata parsing. Source: it is in the vendored
  Ubuntu desktop baseline manifest (`reports/baselines/`, `python3`) and in
  `tests/Dockerfile`. Verification step: its absence fails the step closed
  rather than installing unverified bytes.
