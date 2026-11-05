# AnythingLLM Desktop: integrity for an artifact with no publisher checksum

- Status: accepted
- Deciders: Matias Olivera
- Date: 2026-11-04

## Context and Problem Statement

AnythingLLM Desktop is a GUI application. It ships no apt repository, no `.deb`, and no Flatpak
(Flathub has no `com.mintplexlabs.*` app), so the only distributable is a ~905 MB AppImage. The
vendor publishes no integrity material for it: the `v1.19.0` release lists seven assets and none is
a checksum file, and probes of `https://cdn.anythingllm.com/latest/` for `AnythingLLMDesktop.AppImage.sha256`,
`.zsync` and `checksums.txt` all return `404`.

The repository's integrity rule for setup paths — `docs/decisions/0003-remote-installer-integrity.md`
— requires
installing artifacts verified against the publisher's integrity material, failing closed, and never
executing a remote install script. The vendor's own `installer.sh` violates that rule directly. It is
also unusable from `install.sh`: it is `set -eu` with `read -p` prompts whose count depends on
on-disk state, and it unconditionally fetches roughly 2 GB of local-model engine bundles.

Choice: how to install this artifact without re-opening the unverifiable-execution surface that #44
and issues #45–#50 exist to remove.

## Decision Drivers

- No remote install script may be executed during setup (ADR 0003).
- Verification is mandatory and fails closed; a degraded check is a loud error, not a silent install.
- A 905 MB artifact that the user then executes as a GUI app is expensive to notice as corrupt later.
- Reruns must stay network-free behind the `<stem>_version()` guard (repo script contract).
- Bounded defense goal for a personal environment: remove unverifiable execution, not solve full
  supply-chain security.
- No new runtime prerequisites added to the bootstrap path.

## Considered Options

| Option | Outcome | Cost |
| --- | --- | --- |
| Execute the vendor `installer.sh` | Rejected — remote script execution, the exact thing ADR 0003 removes; interactive prompts at variable counts break non-interactive runs | Zero setup work; pulls ~2 GB of engines nobody asked for |
| Download CDN `/latest/`, verify nothing, file an exception | Rejected — installs bytes nothing attests, adding a new #44-class violation the moment the six existing ones close | Needs an exception record |
| Self-recorded `sha256` pin in the script | Rejected — the hash is authored by us (TOFU), and every release costs a re-audit plus a 905 MB re-download to bump it | Per-release maintenance loop |
| Verify against the `sha256` digest GitHub publishes for the release asset | **Chosen** — GitHub exposes `assets[].digest` to unauthenticated callers; tag and digest come from one response, so the bytes that land equal the bytes that release attests, and no remote script is parsed | Depends on GitHub's digest field; same-channel residual risk |
| Wait for the vendor to publish `SHA256SUMS.txt` | Rejected — blocks the intent indefinitely. Revisit if Mintplex starts publishing checksums | — |

## Decision Outcome

Chosen option: **verify against GitHub's published release-asset digest**, because it is the only
available attestation that keeps the setup path free of remote-script execution while still checking
bytes before they land.

Rules that follow:

- `install_anythingllm` resolves `releases/latest` once and takes the tag and the arch-matched
  asset's `assets[].digest` from that single response — resolving `latest` twice could straddle a
  release published mid-run and fail the check with a misleading error.
- It downloads `releases/download/<tag>/<asset>` to `<name>.part`, verifies with
  `sha256sum --check`, then `chmod +x` and an atomic same-directory `mv`. Missing digest, unknown
  asset, transport failure or mismatch aborts the step and removes the `.part`.
- The artifact lives in `$HOME/Applications`; `ANYTHING_LLM_INSTALL_DIR` is honored for parity with
  the upstream docs.
- Installed version is the tag recorded at install time in
  `${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-config/anythingllm.version`. The AppImage cannot be
  read for a version cheaply and running it needs a display, so the version guard is a file-and-marker
  check and never touches the network.
- The AppArmor profile and the launcher entry are cheap idempotent state and run on every invocation,
  but never overwrite what exists: an existing profile or `.desktop` file is the user's.
- The local-model engines (lemond, llama.cpp, ollama bundles) are deliberately not fetched; the app
  downloads what it needs on first use.

### Positive Consequences

- Setup executes no remote install script, so #44's end state survives the arrival of this app.
- Verification is fail-closed with named errors, matching the compliant pattern issue #6 established.
- ~905 MB instead of ~2.5 GB, and reruns skip the network entirely behind the guard.
- Moving the AppImage later does not break it: the profile keeps upstream's
  `/**/AnythingLLMDesktop.AppImage` path pattern rather than a hard-coded directory.

### Negative Consequences

- GitHub's asset digest is computed at upload by GitHub, not authored by Mintplex. It attests that the
  downloaded bytes match the release asset, not that the release itself is legitimate. ADR 0003 already
  accepts this same-channel residual risk, and it is slightly weaker here because attester and host are
  the same service; signatures/attestations remain the escalation path if that is ever judged
  insufficient.
- Parsing the release metadata needs `python3`. It is present in the vendored Ubuntu desktop baseline
  manifest and in the Docker test image; a stripped host fails closed instead of installing unverified.
- If GitHub renames or drops the `digest` field, installs fail loudly until the script is updated — the
  intended direction of failure, but maintenance.
- A machine that previously ran the vendor installer keeps its `$HOME/AnythingLLMDesktop.AppImage`
  alongside ours in `$HOME/Applications`. Convergence is manual: delete the old artifact and its
  launcher entry, then re-run.
