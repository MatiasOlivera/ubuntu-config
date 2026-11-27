# plan.md - `090-bitwarden-cli-verified-artifact`

## Architecture

Small, local change following the existing verified-artifact scripts (`bun.sh`,
`uv.sh`, `antigravity-cli.sh`). Component order:

1. `tests/python/test_bitwarden_cli_metadata.py` — new unit tests for the
   release-metadata parser (written first, red).
2. `setup/development/bitwarden_cli_metadata.py` — new parser: from the GitHub
   releases array, choose the newest `cli-v*` release, derive the expected
   `bw-bit-linux[-arm64]-<version>.zip` asset for the requested architecture,
   and validate the asset URL and SHA-256 digest before emitting them.
3. `tests/setup/development/bitwarden-cli-test.sh` — new hermetic black-box
   test for the install script (written first, red): stub `curl`, `sudo`, `apt`,
   `unzip`, `uname` and `bw`; fixture release JSON and zip; sandboxed HOME and
   TMPDIR. Covers every acceptance scenario in `spec.md`.
4. `setup/development/bitwarden-cli.sh` — replace `sudo snap install bw` with:
   skip guard → `bitwarden_cli_dependencies` (`apt install -y unzip`) →
   `bitwarden_cli_install_verified` in a subshell with cleanup trap → fetch
   release metadata → parse → download asset → `sha256sum --check` →
   `unzip -tqq` / `unzip -p … bw` → run extracted binary for version → stage in
   `$HOME/.local/bin` → `mv` into place → symlink `/usr/local/bin/bw` for
   non-interactive shells (`sudo ln -sf`, outside the guard, as in
   `antigravity-cli.sh`). The version guard calls the **installed path**
   (`$HOME/.local/bin/bw --version`), not a generic `bw` on PATH, so an existing
   snap install cannot suppress the migration.
5. `specs/090-bitwarden-cli-verified-artifact/{spec,plan,tasks}.md` — the SDD
   artifacts for this issue.

Install data flow, with fail-closed checks at each boundary:

```
skip guard (installed path) → apt unzip
  → GET releases JSON → parser (tag, asset, URL, digest)
  → GET asset → sha256sum --check → unzip -tqq → extract bw
  → run bw -v → stage in ~/.local/bin → mv → symlink /usr/local/bin/bw
```

Not touched: `setup/install.sh` (source line and `step install_bitwarden_cli`
keep their names), `reports/versions.sh` (`src`/`chk` rows keep the same
function name), ADRs 0003/0007/0008, `docs/integrity-exceptions.md`, other
applications' scripts, dotfiles and setup ordering.

Verification order: scoped tests first, then the full `./tests/test.sh` gate,
then a Multipass seed run and a `--reuse` run for idempotency (per `run-tests`).
No snap removal means the e2e VM exercises only the fresh-install path; the
existing-snap case is covered by the hermetic test.

## Data models

None persisted. Transient shapes:

- GitHub release object: `tag_name`, `assets[]` with `name`,
  `browser_download_url`, `digest` (`sha256:<64 hex>`).
- Parser stdout: four tab-separated fields — `<version>\t<asset>\t<url>\t<digest>`;
  any invalid or missing field is a nonzero exit with a named stderr error.
- `bitwarden_cli_version()` stdout: exactly one version line; exit 0 iff the
  verified binary is installed at `$HOME/.local/bin/bw`.

## API contracts

- `GET https://api.github.com/repos/bitwarden/clients/releases?per_page=100`
  with `Accept: application/vnd.github+json`. Returns newest-first JSON array.
  `releases/latest` is not used: this repository publishes web, desktop and
  browser releases alongside CLI releases, so the global latest can be a
  different product. The parser filters `^cli-v[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$`
  and takes the first match.
- Asset selection: `bw-bit-linux-<version>.zip` (amd64) or
  `bw-bit-linux-arm64-<version>.zip` (arm64). The URL must match
  `https://github.com/bitwarden/clients/releases/download/<tag>/<asset>` and
  the digest must match `sha256:[0-9a-fA-F]{64}`; otherwise fail closed.
- Downloaded bytes are checked with `sha256sum --check --status` before any
  extraction. The archive must contain `bw` at its root (Bitwarden's build
  workflow zips `./bw` from the dist directory).
- Scenario mapping: fresh install, missing/mismatched material, unreachable
  metadata, rerun skip and unsupported architecture →
  `tests/setup/development/bitwarden-cli-test.sh`; parser edge cases →
  `tests/python/test_bitwarden_cli_metadata.py`; non-interactive invocation and
  versions report → e2e VM run plus the hermetic symlink/version assertions;
  existing snap preserved → hermetic test with a fake snap `bw` earlier in
  PATH.

## Decisions

No new ADR is created: this applies ADR 0008 rung 3 and ADR 0007's fallback as
written, without changing a policy. Choices settled with the issue owner and
recorded in `spec.md`:

- Verified release artifact, not Homebrew (rung 4, adds a Node dependency and
  relies on Homebrew's own bootstrap), snap (rung 6), or an integrity exception
  (does not meet the issue's preferred-rung goal).
- Commercial `bit` build, not `oss`: same binary the snap wraps, keeps
  device-approval commands.
- Newest `cli-v*` release chosen at install time, not a pinned version constant:
  no manual bumps, while the skip guard keeps reruns network-free.
- Existing snap left in place: removing it would delete snap-stored vault
  configuration; the symlink makes the verified binary win on PATH.
- ADR 0008's rung order is not revisited, and no follow-up issue is filed.

## Risks

- Upstream renames release assets (they did at `cli-v2026.11.0`): the parser
  fails closed with a named error until the asset pattern is updated. Release
  notes are the signal; no silent wrong-arch install.
- GitHub rate limits or API response changes: one unauthenticated request per
  fresh install; failure is loud and the step can be rerun. `per_page=100`
  avoids missing an older CLI release among newer product releases.
- No maintainer checksum asset for CLI releases, so GitHub's asset digest is
  the integrity source (ADR 0007 fallback). Residual same-channel compromise
  risk is accepted there; record the reason and sources checked in the PR.
- `/usr/local/bin/bw` could be shadowed by an unusual user PATH that puts
  `/snap/bin` first. Ubuntu's default order puts `/usr/local/bin` first; check
  in the e2e VM. On machines with both installs, the version guard reads only
  the verified path.
- An unrelated `bw` installed by npm/Homebrew will not satisfy the guard, so
  setup installs its own verified copy; it never removes the other one.
- Rollback: revert the commit; the snap install and its data are untouched.

## Assumptions

- GitHub returns releases newest first, so the first matching `cli-v*` tag is
  the newest CLI release. Source: GitHub REST releases list contract and the
  release page order observed 2026-11-26. Verification: fixture ordering in
  `test_bitwarden_cli_metadata.py` and a live read during implementation.
- The releases array contains the asset `digest` field. Source: `sha256:` shown
  beside each release asset and `antigravity_cli_metadata.py`'s fallback
  parser. Verification: read a live response during implementation; if the
  field is unavailable, fail closed and revisit the approach before coding.
- `unzip` is not guaranteed on a fresh VM. Source: `bun.sh` and `fnm` install it
  via apt. Verification: e2e seed run confirms the dependency step works.
- The remaining load-bearing claims (asset names, archive layout, version
  output, absence of a separate checksum file) are listed with their sources
  and verification steps in `spec.md`.

## PR Verification (draft)

**Install rung:** 3 — checksum-verified release artifact (ADR 0008). The CLI has
no Ubuntu or vendor apt package; the `bw-bit-linux[-arm64]` zip is the highest
available rung. The commercial `bit` build is the exact binary the existing snap
wraps, so behavior (including device approval) is preserved.

**Integrity source:** Bitwarden publishes no separate checksum asset for CLI
releases (expanded assets of `cli-v2026.11.0` and `cli-v2026.11.1`, checked
2026-11-26). Verification therefore uses GitHub's release-asset SHA-256 digest,
the ADR 0007 fallback. Sources checked: `bitwarden.com/help/cli`,
`bitwarden.com/help/security-faqs`, the GitHub release asset lists and Bitwarden's
`build-cli.yml`. No self-authored hash pin and no exception entry are used.

**Verification:** `./tests/test.sh` passed; `./tests/test.sh --vm --keep`
installed `bitwarden-cli 2026.11.1` on a fresh VM and the versions report listed
it; `./tests/test.sh --vm --reuse` skipped the install before any download and
ended with all checks passed. Hermetic tests cover missing/mismatched material,
transport failures, both architectures, rerun skip, PATH invocation and an
existing snap install left untouched.
