# plan.md - `48-install-opencode-from-verified-artifact`

## Architecture

Change `setup/development/opencode.sh` and add the hermetic functional test
`tests/setup/development/opencode-test.sh`. `setup/install.sh` already sources
the script and runs `install_opencode` (`setup/install.sh:73,139`);
`reports/versions.sh` already sources it and checks `opencode_version`
(`reports/versions.sh:69,121`). The test runner automatically executes each
`*-test.sh` under `tests/` (`tests/test.sh:144-152`). No wiring changes are
needed.

Install flow:

1. Keep `opencode_version` as the source of truth. A successful version check
   prints the existing skip message and returns before network access.
2. Map Linux `x86_64`/`amd64` to `x64-baseline` and `aarch64`/`arm64` to
   `arm64`; reject other architectures.
3. Fetch the official V2 formula from
   `https://raw.githubusercontent.com/anomalyco/homebrew-tap/master/opencode-v2.rb`.
   Parse it as text with Python's standard library; never evaluate Ruby. Select
   the exact Linux architecture URL and matching `sha256`. Accept only URLs
   under `https://opencode.ai/files/bin/<version>/` with the expected archive
   name, and a 64-character hexadecimal checksum. Missing, duplicate,
   malformed, or unsupported formula entries fail with a named error. There is
   no GitHub digest fallback in this installer.
4. Download the formula's artifact URL to a private temporary directory and
   verify it with `sha256sum` before extraction. Extract only the archive's
   root `opencode` entry, install it to a staged file under
   `$HOME/.opencode/bin`, run the staged binary's `--version`, then atomically
   move it into place. The V2 upstream installer uses this install directory;
   the existing zsh config adds it to `PATH` (`dotfiles/dot_zshrc:150-151`).
5. Keep install internals in a subshell, matching the Copilot installer
   pattern, so temporary cleanup does not replace `setup/install.sh`'s EXIT
   trap. The outer function removes the temporary directory and returns the
   inner status.

The functional test creates V2 formula text and small tar fixtures, stubs
`curl` and `uname`, and sets a temporary `HOME`/`TMPDIR`. It asserts that only
the formula and selected artifact are requested; it never contacts GitHub's
release API or either remote installer. Coverage includes x64-baseline and
arm64 installs, skip without network, unsupported architecture, missing or
malformed formula data, failed downloads, checksum mismatch, invalid archive,
and no installed binary on failure. The skip guard remains as-is, so a
pre-existing V1 binary also skips; automatic V1-to-V2 migration is outside
scope.

## Data models

- Formula input: Ruby DSL text. The parser extracts one architecture-matched
  Linux `url` and its `sha256`; it does not execute or source the formula.
- Selected artifact URL: `https://opencode.ai/files/bin/<VERSION>/opencode-linux-{x64-baseline,arm64}.tar.gz`.
- Integrity value: exactly 64 hexadecimal characters from the matching V2
  formula `sha256` declaration.
- Installed command: executable `$HOME/.opencode/bin/opencode`; no new marker
  file or persistent metadata.

## API contracts

- Official checksum source: V2 formula in `anomalyco/homebrew-tap` at
  `https://raw.githubusercontent.com/anomalyco/homebrew-tap/master/opencode-v2.rb`.
  The live version `2.3.2` formula inspected on 2026-11-20 specifies the Linux
  x64-baseline URL and checksum, and the Linux arm64 URL and checksum.
- Artifacts: download only the exact URL paired with the selected formula
  checksum. Reject URLs outside `opencode.ai/files/bin/<version>/` or names
  other than `opencode-linux-x64-baseline.tar.gz` and
  `opencode-linux-arm64.tar.gz` for the matching architecture.
- Runtime tools: `curl`, `python3`, `sha256sum`, `tar`, `install`, and standard
  shell utilities. The Ubuntu desktop baseline manifest includes `python3`
  (`reports/baselines/ubuntu-26.04.1-desktop-manifest.txt:1509`).
- Existing interfaces: `install_opencode`, `opencode_version`, and the
  standalone `install|version` dispatcher remain unchanged.
- Upstream compatibility: the V2 installer uses `$HOME/.opencode/bin`
  (`https://opencode.ai/v2/install`, lines 64-65) and maps x64/arm64
  (`lines 81-87`). Official documentation recommends the V2 install endpoint
  and `anomalyco/tap/opencode-v2` (`https://opencode.ai/docs`).

## Decisions

- Apply `docs/decisions/0003-remote-installer-integrity.md`: do not execute the
  remote installer and verify the release artifact before installation.
- Apply `docs/decisions/0007-artifact-integrity-source-priority.md` by using
  the available maintainer-published checksum from the official V2 formula.
  This installer is intentionally scoped to that source and fails closed if
  its checksum is unavailable; it does not implement source selection or a
  GitHub digest fallback.
- Target V2, as clarified by the user. The existing
  `https://opencode.ai/install` endpoint is the legacy V1 installer; the
  official V2 path is `/v2/install` and the V2 Homebrew formula is
  `opencode-v2.rb`.

## Risks

- The Homebrew formula is mutable and its DSL format can change. Restrict the
  parser to the known formula structure and fail closed on absent, duplicate,
  malformed, or mismatched entries; fixtures make format changes visible.
- The formula and artifacts use different publisher endpoints, but both
  remain within OpenCode's distribution/release channels. A compromise of the
  publisher's checksum or artifact channel remains within the residual risk in
  decision 0003.
- Formula updates can precede or lag artifact availability. The formula URL
  and checksum define the selected version; an unavailable artifact fails the
  step without installing anything.
- A pre-existing V1 `opencode` remains untouched because the preserved
  version-based skip guard treats any working installation as installed.
