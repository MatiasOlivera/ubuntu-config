# plan.md - `08-language-package-managers`

## Architecture

- **New installers** (one source-only script each, dispatcher guard at the
  bottom, mirroring `setup/development/uv.sh` and `fnm/install-fnm.sh`):
  - `setup/development/pnpm.sh` — `install_pnpm`, `pnpm_version`, and a release
    metadata helper. Installs into `$HOME/.local/bin/pnpm`, the same user path
    uv uses (`uv.sh:67-85`); `dot_zshrc:129` already puts it on the shell PATH.
  - `setup/development/bun.sh` — `install_bun`, `bun_version`, an
    `bun_dependencies()` apt helper for `unzip` (pattern: `fnm_dependencies`
    at `fnm/install-fnm.sh:5-7`), and a release/checksum metadata helper.
    Installs to `$HOME/.bun/bin/bun` and `$HOME/.bun/_bun` so the existing
    `dot_zshrc:154-159` completions and PATH exports resolve.
- **Version guards** must prepend the install dir inside a subshell before
  calling the binary: neither `~/.local/bin` nor `~/.bun/bin` is on the
  non-login PATH of `install.sh`. This is the reason `uv_version` does it
  (`uv.sh:88-94`); copy that pattern rather than relying on rc files.
- **Integrity path** (ADR 0003/0007, `docs/decisions/0003-remote-installer-integrity.md`
  and `0007-artifact-integrity-source-priority.md`):
  - bun: one `releases/latest` response for tag + asset list; download the
    publisher's `SHASUMS256.txt` and the arch-matched `bun-linux-*.zip`;
    `sha256sum -c` must pass before extraction. Fail closed on missing or
    mismatched checksum. Publisher material is checked first (ADR 0007).
  - pnpm: its releases publish no checksum file (verified on the `pnpm/pnpm`
    latest release, `v12.21.0`, 2026-11-20), so use GitHub's `sha256:` asset
    `digest` from the same release response — the ADR 0007 fallback. Validate
    the digest format and that the download URL matches the release tag before
    use, as `fnm_release_asset_info` does (`fnm/install-fnm.sh:35-86`).
  - Both: fetch metadata once, use a private temp dir, stage the binary as
    `.part`, verify, then `mv -f` into place; never execute a remote script.
- **Wiring**: `source` + `step install_pnpm` and `step install_bun` in the
  Development phase of `setup/install.sh` (alongside `uv` at lines 72/138).
  `src`/`chk` pairs in `reports/versions.sh` (pattern: lines 68/120).
- **Docs**: new `docs/language-package-managers.md` — the live, authoritative
  policy: per-language default, compatibility fallbacks, rejected options with
  reasons, tie-breakers, "other languages decided when needed", and links to
  ADR 0003/0007 for install integrity. README: add both managers to the
  Development list and link the policy. AGENTS.md: add the policy to Rules and
  amend the Decisions section so policy-type documents are authoritative for
  language managers.
- **Tests**: `tests/setup/development/pnpm-test.sh` and `bun-test.sh`,
  network-stubbed and temp-dir isolated per `tests/AGENTS.md`. `tests/test.sh`
  discovers every `*-test.sh` automatically (`:144-152`); no registration.

## Data models

None. Both installers persist only the binary (and bun's completion script);
no version marker files are needed because `<name>_version` works after
install, as with uv.

## API contracts

- Dispatcher: `install_*` / `*_version` functions plus the `BASH_SOURCE` guard
  (`setup/helpers/dispatcher.sh:3-56`; contract enforced by `tests/test.sh:94-121`).
- Report: one `src <path>` and one `chk "<label>" <stem>_version` pair per
  manager (`reports/versions.sh:31-33`, `:83-133`).
- Test suites stub `curl`, extraction tools, and `uname`; unexpected network
  access fails the test.

## Decisions

No MADR is created. The live policy document is the decision artifact, per the
user's explicit choice; AGENTS.md is updated so the rule matches the practice.
The document records: uv (pip/pipx rejected as defaults but kept as fallbacks
for agents), pnpm (npm/Yarn/Bun rejected as default, verified install),
bun installed only because existing dotfile config references it, fnm kept as
Node version manager (pnpm runtime rejected for now: no npm/npx/corepack), and
other languages deferred until a script needs them.

## Risks

- pnpm's only integrity material is GitHub's asset digest, which attests bytes
  GitHub hosts, not the maintainer's intent (ADR 0007 negative consequence).
  Record this in the policy doc; revisit if pnpm publishes checksums.
- Archive layouts (bun zip binary/completion paths; pnpm tarball binary path)
  are unverified locally. Inspect the actual artifacts during implementation;
  fail with a named error and leave no partial install if the expected entry
  is absent.
- A stubbed suite cannot prove live GitHub API/release contracts. The Multipass
  e2e run is the real check; keep its failures loud.
- Keeping bun and pip/pipx installed means the machine carries tools beyond
  the "default" picks. Explicitly labelled as compatibility/legacy fallbacks
  in the policy doc to avoid silent drift.

## Assumptions

- Repo state: base tip `bdfaaf8687c6015daae599ccdd6e5feb5b847a3a`; uv already
  wired at `setup/install.sh:72,138`; pip/pipx at `:41-42,91-92`; bun block at
  `dotfiles/dot_zshrc:154-159`. Source: local checkout read on 2026-11-20.
- bun release `bun-v1.4.5` lists `bun-linux-x64.zip`, `bun-linux-aarch64.zip`
  and `SHASUMS256.txt`; pnpm `v12.21.0` lists `pnpm-linux-x64.tar.gz` and
  `pnpm-linux-arm64.tar.gz` with GitHub `sha256:` digests. Source: GitHub
  releases API, fetched 2026-11-20. Verify again against the release selected
  during implementation.
- Python 3 is present in the vendored Ubuntu baseline
  (`reports/baselines/ubuntu-26.04.1-desktop-manifest.txt`), so metadata
  parsers can reuse it as uv/fnm do. Verify by rerunning the isolated suite.
