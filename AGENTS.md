# ubuntu-config

Infrastructure-as-code setup for a fresh Ubuntu workstation: versioned bash scripts in `setup/` install `apt` packages, Flatpak/Snap apps and dev tools; declarative chezmoi dotfiles in `dotfiles/` own the configuration. Scripts assume Ubuntu with `apt` + `sudo`. Humans: see `README.md` (commands, reports, project structure).

## Architecture

> [Architecture] Uses Plugin (partial)

## Shared conventions

Follow the shared
[workflow](https://github.com/MatiasOlivera/standards/blob/main/docs/workflows/README.md).
Apply it alongside the project-specific rules in this file. This file defines
local architecture, commands, and approval requirements.

Shared conventions: MatiasOlivera/standards — repo conventions defer to it; file cross-project issues there, project issues here. Read its content from the local checkout at ~/Documents/Projects/standards first; use the github.com/MatiasOlivera/standards remote only for filing and verification.

## Constitution

[`specs/constitution.md`](specs/constitution.md) is the binding charter for this
repository: it takes precedence over this file and `.agents/skills/`, and the
rules below are concrete operational detail that must honor its axioms.
The shared workflow above governs cross-repo process; the constitution
governs this repository.

## Commands

Anything beyond verify (adding apps, reports, baselines): `README.md` ("Testing", "Reports").

Releases: `scripts/release.sh` owns prepare and preview; the promotion merge into
`main` triggers `release.yml` to tag, publish and merge back. Do not cut tags or
releases by hand — see `docs/runbooks/release-runbook.md`.

## End-to-end observability

Each `./tests/test.sh --vm` phase records per-app spans, logs and a summary under
`E2E_OBSERVABILITY_DIR` (default
`${XDG_DATA_HOME:-$HOME/.local/share}/ubuntu-config/observability/<run-id>/`) and
prints `records:` and `log:` paths. Start the local stack before or after a run
to browse traces, correlated logs and metrics in Grafana:

```sh
docker compose -f tests/observability/compose.yml up -d
# Grafana: http://localhost:3000 (admin/admin)
```

Live forwarding from the VM is best effort: an unreachable collector warns once
and durable records stay complete. Stop with
`docker compose -f tests/observability/compose.yml down`.

## Rules

Declarative-vs-imperative placement follows infrastructure-as-code principles.

- Declarative files → chezmoi in `dotfiles/` (`dot_*` → `$HOME`, `*.tmpl` rendered with `~/.config/chezmoi/chezmoi.toml` data); imperative commands (`chsh`, `gsettings`, clones) → stay in bash.
- Public repo: never commit secrets. Root `.gitignore` (commit deny-list) and `dotfiles/.chezmoiignore` (deploy deny-list) must stay in sync when adding dotfiles.
- Setup scripts stay rerun-safe and source-only. The host `tests/test.sh` check sources library scripts, so run it only on trusted checkouts.
- Language package-manager choices (uv/pnpm/bun/fnm, pip/pipx fallbacks) follow the live policy in `docs/language-package-managers.md`; update that file when a pick changes.

## Execution environment

MUST NOT run system-mutating `setup/` scripts (`install.sh`, `post-install.sh`, app install/config scripts) on the host machine: run them in Docker or Multipass instead. `tests/test.sh` and `reports/versions.sh` source library scripts, so run them only on trusted checkouts — for untrusted changes use `docker compose -f tests/compose.yml run --rm test` (the Multipass loop runs host-side checks before entering the VM, so it is trusted-checkout-only as well). `bash -n`, shellcheck, the grep-based contract checks, and `reports/gaps.sh` do not execute repo code and are host-safe on any checkout.

The root `opencode.json` adds command denials for setup scripts and selected host-mutating commands (`sudo`, `apt`, `apt-get`, `snap`, `chsh`). It is a command filter, not an OS sandbox; use Docker or Multipass for system-mutating work.

## For changes

- Run focused checks on the changed files while implementing.
- Run the full gate before the first local review, stopping at the first failure.
- Rerun the full gate before the pull request only when review feedback changed code.
- When a change invalidates agent-facing docs (`AGENTS.md`, `.agents/skills/`), update them in the same PR.

## Version control

- Use atomic Conventional Commits
- Split commits by semantic concern; each commit must be independently revertable.
  Group only what cannot land separately.
- Explain the why in the body whenever a commit needs justification: bug fixes
  (symptom + root cause + why this fix), refactors, renames, sequencing changes.
  2–4 sentences. Omit the how - the diff shows it.
- Use Git flow for branches off `develop`: `<type>/<[issue-]slug>`; release
  only as `develop` → `main`. `slug` = kebab-case title: lowercase,
  non-alphanumerics → `-`, capped at ~5 words / 60 chars. Branch `<type>` and
  pull request title `<type>` follow Conventional Branch, not the commit type.
- Never commit without explicit approval

## Docs

README.md and docs are for humans; AGENTS.md and skills are for coding agents

## Decisions

Non-trivial choices (stack, protocol, workflow) MUST be recorded as MADR records
in `docs/decisions/` (`NNNN-slug.md`); overturns note "supersedes `NNNN-…`" in
prose.
Policy-type decisions that must stay current — notably language package-manager
picks — live in `docs/language-package-managers.md` instead; that file is the
authoritative source for those choices.
