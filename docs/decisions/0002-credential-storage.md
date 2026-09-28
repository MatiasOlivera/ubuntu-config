# Credential storage: files vs keyring vs vault

- Status: accepted
- Deciders: Matias Olivera
- Date: 2026-09-28

## Context and Problem Statement

Setup needs a standard place to keep machine secrets (API tokens, PATs). The first consumer is the GitHub MCP personal access token shared by opencode, agy, and Copilot CLI. We need one rule that works for this token and every secret after it.

## Decision Drivers

- Public repository: secrets must never be committable; root `.gitignore` and `dotfiles/.chezmoiignore` deny-lists must stay in sync.
- Fresh-Ubuntu reinstalls must reproduce the setup without re-inventing storage per secret.
- Shell startup must stay fast and non-interactive; locked-vault prompts on every shell are unacceptable.
- Ubuntu desktop auto-unlocks the login keyring; the user already keeps a synced Bitwarden vault.

## Considered Options

| Option | Outcome | Cost |
| ------ | ------- | ---- |
| Plaintext in files (`export` in `.zshrc`, `.env`) | Lost: leaks via history, backups, dotfiles copies; every process inherits it | Zero setup, highest leak risk |
| OS keyring only (GNOME Keyring via `secret-tool`) | Lost: local-only, dies on reinstall, no sync or sharing | One apt package, zero friction |
| External vault CLI in hot path (`bw` unlock each shell) | Lost: master-password/session handling on every shell, breaks non-interactive shells | Sync kept, startup friction |
| **Hybrid: vault as durable copy, keyring as runtime** | Won: sync plus frictionless auto-unlock; repo holds only install steps and lookups | Two packages, one manual bridge step per machine |

## Decision Outcome

Chosen option: **hybrid vault + keyring**, because it is the only option that keeps synced backup without taxing every shell startup.

- Durable copy lives in Bitwarden (item per secret); runtime copy lives in GNOME Keyring (`service`/`account` per secret).
- Repo codifies install steps (`libsecret-tools`, Bitwarden CLI) and lookup snippets only; per-machine bridge (`bw get ... | secret-tool store ...`) is a documented manual step.
- First usage: GitHub MCP PAT as `GITHUB_PAT_FOR_CODING_AGENTS`, keyring `service github-mcp / account personal-access-token`, Bitwarden item `github-mcp-pat`.

### Positive Consequences

- No secret bytes in the repo, history, or backups; rotation means updating two stores, not N configs.
- Runtime lookup is one `secret-tool` call with login-session unlock; `gh` already sets the precedent.

### Negative Consequences

- Two stores to install and understand; mitigation is the single bridge command in the setup docs.
- Exported env vars remain visible to same-user processes while set; per-command scoping is future hardening, not v1.
