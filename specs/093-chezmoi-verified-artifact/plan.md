# plan.md - `093-chezmoi-verified-artifact`

## Architecture

Small, local change following the existing verified-artifact scripts
(`bitwarden-cli.sh`, `opencode.sh`, `uv.sh`). Component order:

1. `tests/python/test_chezmoi_metadata.py` — new unit tests for the metadata
   parser, written first (red).
2. `setup/essentials/chezmoi_metadata.py` — new parser with two modes:
   `release` selects the current release's Linux artifact and its checksums
   asset from GitHub's `releases/latest` object; `checksum` extracts the one
   maintainer digest line for that exact asset. Both modes fail closed on any
   missing, malformed or ambiguous field.
3. `tests/setup/essentials/chezmoi-test.sh` — new hermetic black-box test for
   the install script, written first (red): stub `curl`, `sudo`, `uname` and a
   fake installed binary; fixture release JSON, checksums file and tar.gz;
   sandboxed HOME and TMPDIR. Covers every acceptance scenario in `spec.md`.
4. `setup/essentials/chezmoi.sh` — replace the `curl … | sh` installer with:
   skip guard → tool/arch checks → fetch release JSON → parser `release` →
   fetch checksums file → parser `checksum` → fetch archive →
   `sha256sum --check` → extract `chezmoi` → run it for a version →
   `sudo install -m 0755` into `/usr/local/bin/chezmoi`. The install runs in a
   subshell with temp cleanup; `chezmoi_version()` is unchanged.
5. `specs/093-chezmoi-verified-artifact/{spec,plan,tasks}.md` — the SDD
   artifacts for this issue.

Data flow, with fail-closed checks at each boundary:

```
skip guard → GET releases/latest → parser release (version, asset, urls)
  → GET checksums → parser checksum (digest) → GET archive
  → sha256sum --check → tar extract chezmoi → run --version
  → sudo install /usr/local/bin/chezmoi
```

Not touched: `setup/install.sh` (same source line and step name),
`reports/versions.sh` (same `src`/`chk` function name), ADRs 0003/0007/0008,
`docs/integrity-exceptions.md`, other applications' scripts, setup ordering,
dotfiles and README.

Verification order: scoped tests first, then the full `./tests/test.sh` gate,
then a Multipass seed run and a `--reuse` run for idempotency (per `run-tests`).

## Data models

None persisted. Transient shapes:

- Release object from `releases/latest`: `tag_name`, `assets[]` with `name`
  and `browser_download_url`.
- Parser `release` stdout: four tab-separated fields —
  `<version>\t<asset>\t<artifact_url>\t<checksums_url>`.
- Parser `checksum` stdout: one lowercase 64-hex digest.
- `chezmoi_version()` stdout: exactly one version line; exit 0 iff `chezmoi`
  is callable. Unchanged from today, so the versions report needs no edit.

## API contracts

- `GET https://api.github.com/repos/twpayne/chezmoi/releases/latest` with
  `Accept: application/vnd.github+json`. One unauthenticated request per fresh
  install; the skip guard prevents it on reruns.
- Tag format: `^v([0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?)$`; the capture
  is the version. Architecture comes from `uname -m`: `x86_64|amd64 → amd64`,
  `aarch64|arm64 → arm64`, anything else fails closed.
- Asset names: `chezmoi_<version>_linux_<arch>.tar.gz` and
  `chezmoi_<version>_checksums.txt`. Each must appear exactly once, and each
  URL must equal `https://github.com/twpayne/chezmoi/releases/download/<tag>/<name>`.
- Checksum file lines are `<64 hex>  <asset name>`. The digest for the exact
  artifact asset must appear exactly once; the shell writes that digest into a
  one-line checksum file and runs `sha256sum --check --status` before any
  extraction. `--ignore-missing` is not used: the real checksum file lists
  many assets, and GNU `sha256sum` exits nonzero for missing entries even
  with that flag (observed locally this session: a valid-format checksum line
  for a missing file exits 1).
- The archive must contain a top-level `chezmoi` binary; the extracted binary
  must run `--version` and print one line before it is installed.
- Scenario mapping: fresh install, missing/mismatched material, unreachable
  metadata, rerun skip, unsupported architecture, non-interactive shell and
  single-line version → `tests/setup/essentials/chezmoi-test.sh`; parser edge
  cases → `tests/python/test_chezmoi_metadata.py`; versions report → e2e VM.

## Decisions

No new ADR is created: this applies ADR 0008 rung 3, ADR 0007's preference for
maintainer-published material and ADR 0003's checksum rule as written, without
changing a policy. Choices settled with the issue owner and recorded in
`spec.md`:

- Checksum-verified release artifact, not the exception path (checksums exist),
  Homebrew (lower rung, installed later in the run), snap or raw `.deb` (lower
  rungs).
- Maintainer-published checksum file, not GitHub's asset digest fallback or
  cosign signatures (ADR 0003 rejected signature verification for now).
- Newest release chosen at install time, not a pinned version constant: no
  manual bumps, while the skip guard keeps reruns network-free.
- Keep `/usr/local/bin/chezmoi` rather than `$HOME/.local/bin` + symlink:
  `install.sh` invokes `chezmoi` from a non-interactive shell and already has
  sudo at this step (`setup/install.sh:12-14,166`).
- ADR 0008's rung order is not revisited and no follow-up issue is filed.

## Risks

- Upstream renames the archive or checksum asset, or stops publishing the
  checksum file: both parsers fail closed with a named error until the
  contract is updated. Release assets are the signal; no silent wrong-arch
  install.
- GitHub rate limits or an API response change: one unauthenticated request
  per fresh install; failure is loud and the step can be rerun.
- A pre-existing chezmoi placed by the old remote installer already satisfies
  the version guard, so its bytes are not replaced on a rerun. This change
  guarantees the verified path on fresh installs and on machines with no
  existing chezmoi; migrating old installs would need a provenance marker and
  is out of scope unless requested.
- `/usr/local/bin` requires sudo; the installer already holds a sudo
  keepalive, and the binary is only installed after its version check passes.
- Python 3 is required at this early bootstrap step. Ubuntu cloud images used
  by the e2e harness carry it for cloud-init; if it is absent the step fails
  closed with a named error before any download. No apt dependency step is
  added because `apt update` happens later in `install.sh`.
- Rollback: revert the commit; a previously installed `/usr/local/bin/chezmoi`
  is untouched by a failed or reverted run.

## Assumptions

- GitHub's `releases/latest` response has the `tag_name` and `assets[]` fields
  used by the parser. Source: live API response for `v2.74.2` fetched
  2026-11-26. Verification: read the live response during implementation;
  fail closed and revisit if the shape changes.
- The checksums file lists `chezmoi_<version>_linux_<arch>.tar.gz` with a
  64-hex digest. Source: `chezmoi_2.74.2_checksums.txt` fetched from the
  release on 2026-11-26. Verification: fixture in the unit tests and a live
  read before implementation.
- `tar -xzf <archive> -C <tmp> chezmoi` extracts a top-level binary. Source:
  chezmoi's "Download a pre-built binary" documentation and the release asset
  list, read 2026-11-26. Verification: hermetic fixture and e2e VM run.
- Python 3 is available before the first `apt update`. Source: the Multipass
  26.04 cloud image used by `tests/test.sh`. Verification: e2e seed run; the
  hermetic test stubs nothing here because it uses the host's python3.
- The load-bearing policy claims (no Ubuntu/vendor apt rung, no exception
  needed) are cited in `spec.md` with their sources and verification steps.

## PR Verification (draft)

**Install rung:** 3 — checksum-verified release artifact (ADR 0008). Ubuntu's
stable suites do not carry chezmoi and the publisher documents no apt
repository, so the two distribution rungs are unavailable. The remote
installer is gone; the exception register is untouched.

**Integrity source:** maintainer-published `chezmoi_<version>_checksums.txt`
(ADR 0007 preferred source), verified with `sha256sum --check` before any
extraction. Sources checked: chezmoi's install page ("Verify your download"),
the `v2.74.2` release asset list and checksum file, and packages.ubuntu.com,
all read 2026-11-26. No GitHub digest fallback, no self-authored hash pin and
no cosign dependency.

**Verification:** `./tests/test.sh` and
`docker compose -f tests/compose.yml run --rm test` both exited 0.
`./tests/test.sh --vm --keep` installed chezmoi 2.74.2 from the verified
artifact and the versions report listed it; `./tests/test.sh --vm --reuse`
skipped the install before any download and both runs ended with all checks
passed. Hermetic tests cover missing/mismatched material, unreachable
metadata, rerun skip, both architectures, unsupported architecture,
non-interactive invocation and one-line version output.

**Acceptance self-review:** every scenario in `spec.md` maps to a passing
hermetic assertion or a VM observation; the seven scenarios are covered by
`tests/setup/essentials/chezmoi-test.sh` and the versions report in the seed
run. The only uncovered case is migration of a binary left by the old remote
installer, recorded as an out-of-scope risk in `plan.md`.
