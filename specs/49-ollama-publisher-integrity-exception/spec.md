# spec.md - `49-ollama-publisher-integrity-exception`

## Context

Issue: [#49](https://github.com/MatiasOlivera/ubuntu-config/issues/49)

The current Ollama setup step invokes `https://ollama.com/install.sh` directly.
Issue #49 proposed replacing it with publisher-verified artifacts. After
reviewing the upstream installer's behavior, the user chose to retain the
official installer and record Ollama in the repository's integrity-exception
register so its supported hardware setup is not lost through a partial
reimplementation.

The official Linux installer detects supported NVIDIA and AMD GPUs, selects
ROCm or JetPack bundles where applicable, may install NVIDIA drivers, and
configures the Ollama service. The current upstream installer does not verify
the bytes it downloads. Ollama's release workflow does publish a
`sha256sum.txt` for release assets, including bundles and `install.sh`, but
that manifest is not consumed by the current `ollama.com/install.sh` path
([installer](https://github.com/ollama/ollama/blob/main/scripts/install.sh),
[release workflow](https://github.com/ollama/ollama/blob/main/.github/workflows/release.yaml),
reviewed 2026-11-20).

## User stories

- As a person setting up a fresh Ubuntu workstation, I want Ollama installed
  through its official installer so its service and supported hardware setup
  work as upstream intends.
- As a person with a supported NVIDIA, AMD, or JetPack system, I want the
  upstream installer to select its matching runtime bundle and perform its
  documented driver setup where required.
- As a person rerunning setup, I want an existing Ollama installation to be
  skipped without a network request.
- As a reviewer, I want the accepted integrity exception and its risk recorded
  so the setup's trust boundary is visible and can be revisited.

## Acceptance criteria (BDD)

```gherkin
Scenario: fresh installation retains official upstream setup behavior
  Given Ollama is not installed
  When the Ollama setup step runs
  Then the official Ollama installation flow completes
  And the `ollama` command is available
  And the Ollama service is available when systemd is running

Scenario: supported GPU setup follows upstream detection
  Given the machine has a GPU supported by the official Linux installer
  When the Ollama setup step runs
  Then Ollama's upstream flow selects the applicable GPU runtime bundle
  And performs any driver setup that upstream requires for that hardware

Scenario: already installed Ollama skips without network access
  Given `ollama --version` reports an installed version
  When the Ollama setup step runs
  Then it reports the existing skip result
  And it makes no network request

Scenario: accepted integrity exception is documented
  Given the setup retains the upstream installer and its unverified downloads
  When a maintainer reviews the integrity-exception register
  Then Ollama's exception and its accepted risk are described
  And the review date and upstream integrity evidence are recorded
```

## Constraints

- [ ] Preserve the existing version-based skip guard and standalone dispatcher
      contract.
- [ ] Retain upstream Linux hardware detection, ROCm and JetPack bundle
      selection, NVIDIA driver setup, and systemd behavior.
- [ ] Document the accepted risk: the setup does not verify the remote
      installer or the artifacts it downloads, even though Ollama publishes
      release checksum material that the installer does not consume.
- [ ] Keep the exception specific to Ollama and reviewable against current
      upstream behavior and integrity material.
- [ ] Out of scope: changing Ollama functionality or adding an automatic
      upgrade path for an already-installed Ollama.
