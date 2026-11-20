# plan.md - `49-ollama-publisher-integrity-exception`

## Architecture

No setup code changes. `setup/development/ollama.sh` already executes the
official installer behind the version skip guard and dispatcher, which is the
behavior the approved spec requires; it stays exactly as it is
(`setup/development/ollama.sh`).

The only repository change is documentation:

1. Widen the one-line scope statement in `docs/integrity-exceptions.md` so the
   register covers both tools with no publisher integrity material and tools
   where the verified path would discard required upstream setup.
2. Add an Ollama row to the register's `## Entries` table, recording the review
   date, the reason (publisher checksums exist but the installer does not
   consume them; a verified-artifact install would drop GPU detection, ROCm and
   JetPack bundle selection, NVIDIA driver setup, and the systemd service), and
   the accepted risk.

`README.md` already links the register from its Security section, so it needs no
change. No new functional test: the install path is untouched, so the existing
contract checks in `./tests/test.sh` plus the unchanged e2e coverage are the
relevant checks. Adding a hermetic test for unchanged code would not verify any
new behavior.

## Data models

None. The change adds one table row; no persisted state, schema, or version
marker is introduced.

## API contracts

Integrity-exception register columns (`docs/integrity-exceptions.md`):

| Column | Ollama value |
| --- | --- |
| Application | Ollama |
| Version reviewed | unpinned — the installer fetches the current release; `OLLAMA_VERSION` is the upstream pin knob |
| Checked on | 2026-11-20 |
| Why a verified install is unavailable | Upstream publishes `sha256sum.txt` for release assets, but `ollama.com/install.sh` does not consume it. A verified-artifact install would replace upstream hardware detection, ROCm/JetPack bundle selection, NVIDIA driver setup, and systemd configuration with a partial reimplementation. |
| Upstream request | none filed; re-evaluate if the official installer starts verifying the published checksums |

Upstream behavior the exception preserves, from the installer source fetched
2026-11-20 (`https://raw.githubusercontent.com/ollama/ollama/main/scripts/install.sh`):
base `.tar.zst`/`.tgz` bundle, JetPack 5/6 bundles via `/etc/nv_tegra_release`,
GPU detection via `lspci`/`lshw`/`nvidia-smi`, ROCm bundle for AMD, NVIDIA CUDA
repository/driver installation for supported distributions, systemd user/service
setup including `render`/`video`/`ollama` groups. None of that is verified by the
installer.

Publisher integrity material, from the release workflow fetched 2026-11-20
(`https://raw.githubusercontent.com/ollama/ollama/main/.github/workflows/release.yaml`):
a `sha256sum.txt` is generated over all release assets, including `install.sh`,
and uploaded last. It is not referenced by the installer.

Applicable repo rules: ADR 0003 (no remote-script execution) and ADR 0007
(maintainer integrity first, GitHub digest fallback) remain in force for all
other tools; this entry is a scoped exception, not a repeal.

## Decisions

- No new decision record. The user chose to record this as a row in the existing
  integrity-exception register, which is already the durable artifact for this
  class of decision and is linked from README's Security section. The register
  row carries the rationale and accepted risk; no fact is duplicated into a new
  ADR.

## Risks

- A compromise of Ollama's site or release delivery could cause unverified code
  to run with the setup user's privileges. This is the accepted risk recorded in
  the register; mitigation is periodic re-review, not a code control.
- The exception is broader than the register's original "no publisher material"
  case (material exists here). The widened scope sentence and the explicit
  reason keep the register honest.
- Upstream installer behavior drifts: a future installer that verifies its
  downloads, or one that changes its GPU/service steps, invalidates the reason.
  Verification: re-read the installer source when the exception is reviewed and
  update the row's date and reason.

## Assumptions

- The preserved GPU and service steps work on the target hardware. Not exercised
  in a hermetic or GPU-less environment. Verification: the installer source
  above plus a manual run on a machine with the relevant GPU; this issue does
  not add GPU-hardware coverage.
