# Language package managers

> Live policy for language-ecosystem tooling. Update this file when a pick
> changes instead of scattering replacements across decision records. Last
> reviewed: 2026-11-20 (issue #8).

## Defaults

| Ecosystem | Default tool | Also installed | Notes |
| --- | --- | --- | --- |
| Python packages and tools | uv | pip, pipx | pip/pipx remain as compatibility fallbacks for coding agents and legacy commands. |
| Node.js versions | fnm | — | fnm stays the version manager; do not replace it with a package-manager runtime feature. |
| JavaScript/TypeScript packages | pnpm | bun | bun is installed because `dot_zshrc` already configures it; it is not the default for new scripts. |
| Rust, Go, other ecosystems | not decided | — | Decide when a setup script first needs one; do not install speculatively. |

## Why these picks

- **Python — uv.** One verified binary covers environments, packages, and tool
  installs. Rejected: pip/pipx as defaults (no single tool for all three roles,
  and their command names are still needed by agents); Poetry/Pipenv (heavier
  project workflows than a workstation setup needs).
- **JavaScript/TypeScript — pnpm.** Fast, strict, drop-in package manager that
  keeps the existing fnm-managed Node runtime. Rejected: npm (slower default),
  Yarn (legacy momentum), Bun as the default (an all-in-one runtime decision
  with lower measured usage). Bun is installed separately only to make the
  existing shell configuration live.
- **Node versions — fnm.** Already verified, wired into `post-install.sh`, and
  reported in `versions.sh`. Rejected for now: pnpm's runtime management,
  because its Node install path does not provide npm/npx/corepack that agents
  commonly use.
- **Other languages.** No policy until a script needs one; keep the install
  path lazy and user-space first.

## Rules for new setup scripts

1. Use the default in the table. Any deviation must be justified in the PR and
   recorded here if it becomes a pattern.
2. Keep installs idempotent, non-interactive, verifiable, and user-space first.
   Follow the install-package contract (`<stem>_version()` guard, dispatcher,
   wiring in `install.sh`/`post-install.sh`, `src`/`chk` rows in `versions.sh`).
3. Never execute an unverified remote install script. Verify release bytes
   against publisher integrity material first, then GitHub's release-asset
   SHA-256 digest where the publisher provides none, as required by
   [ADR 0003](decisions/0003-remote-installer-integrity.md) and
   [ADR 0007](decisions/0007-artifact-integrity-source-priority.md).
4. OS-level install-method choices follow the [install-method priority](decisions/0008-install-method-priority.md) and the `install-package` skill, not this policy.

## Integrity notes

- uv and bun install from publisher-published checksums.
- pnpm publishes no checksum file for its release tarballs, so its install uses
  GitHub's release-asset SHA-256 digest (the ADR 0007 fallback). This attests
  the bytes GitHub hosts; revisit if the publisher starts shipping checksums.
