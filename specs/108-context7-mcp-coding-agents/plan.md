# plan.md - `108-context7-mcp-coding-agents`

## Architecture

Two existing chezmoi source files are synced from the working machine state;
nothing new is installed and no new dotfile is created. A hermetic contract test
guards the result, and README documents the one-time browser sign-in.

| Component | Change |
| --- | --- |
| `dotfiles/dot_config/opencode/opencode.json` (existing) | Add `mcp.servers.context7` (remote OAuth) and the local `playwright` entry; keep `github` and `sofa` as-is |
| `dotfiles/dot_copilot/mcp-config.json` (existing) | Add `mcpServers.context7` (remote HTTP OAuth, explicit tools); keep `github` as-is |
| `tests/agents/context7-mcp-config-test.sh` (new) | Hermetic contract test, auto-discovered by `tests/test.sh` |
| `README.md` (existing) | Add the Copilot mapping row, Context7 entries and the one-time sign-in step |

Data flow: `chezmoi apply` writes the two global agent config files; each agent
discovers the remote OAuth server from its own config; the user completes a
one-time browser sign-in and the agent stores its tokens outside the repository;
tool calls go to `https://mcp.context7.com/mcp/oauth`. No setup script, keyring
entry, credential-sync row or deny-list changes.

Sequence: failing contract test → sync the two configs → README → full gate →
manual machine verification (apply, sign-in, docs query).

## Data models

None. The change is declarative configuration plus documentation; no persisted
application data or migration is involved.

## API contracts

Upstream server: `https://mcp.context7.com/mcp/oauth`, remote streamable HTTP
with OAuth 2.0. Two tools: `resolve-library-id` then `query-docs`. No API key
and no local stdio transport (Context7 `/docs/howto/oauth` and
`/docs/resources/all-clients`, fetched 2026-11-24).

Per-agent shapes (both copied from the working entries on this machine, verified
by `diff` against the source files):

| Agent | Config shape | Notes |
| --- | --- | --- |
| opencode | `mcp.servers.context7 = { "type": "remote", "url": "<OAuth endpoint>" }` | OAuth is on by default for remote servers; tokens are stored outside project config. `github`, `sofa` and `playwright` are preserved. |
| Copilot CLI | `mcpServers.context7 = { "type": "http", "url": "<OAuth endpoint>", "tools": ["query-docs", "resolve-library-id"] }` | Tools narrowed from the local `["*"]` to the documented pair. `github` is preserved. |

Acceptance mapping: the fresh-machine and reapply scenarios map to the two
synced source files and the contract test; the opencode and Copilot query
scenarios map to the manual sign-in and docs check; the no-credential scenario
maps to the contract test's absence assertions; the gate scenario maps to
`./tests/test.sh`.

## Decisions

None. This applies the existing single-owner, declarative-configuration rule in
`docs/decisions/0015-infrastructure-as-code-principles.md`, and keeps #106's
repo-scoped placement for credential-bearing development tooling. Scope
(opencode + Copilot CLI), one-time browser sign-in, syncing the existing local
entries including `playwright`, and narrowing Copilot's tool list are recorded
in `spec.md`; no new decision record is warranted for a config change.

## Risks

- Copilot CLI's OAuth flow is provisional: Context7 lists it as a supported
  client, but upstream examples show an API-key entry. Mitigation: verify with
  `copilot mcp list` and a docs query after sign-in; opencode is the primary
  verified agent.
- Chezmoi uses a 1:1 source-to-target mapping and plain files are copied
  verbatim, so future local-only edits to either managed file are lost on
  apply. Mitigation: the contract test asserts all expected entries, and README
  says to sync local additions into the source.
- The `playwright` entry uses an unpinned `npx` command. It is declarative
  config only — no setup script executes it — but committing it is a wider diff
  than issue #108 strictly needs.
- OAuth sign-in cannot happen in the headless e2e VM. Mitigation: verify config
  presence in the VM, and do the docs query on the development machine.
- Context7 has usage quotas; a free account includes a monthly allowance. No
  change is needed here, but a quota error is an auth-independent failure mode.

## Assumptions

- Context7's OAuth endpoint is `https://mcp.context7.com/mcp/oauth` and OAuth
  works only over remote HTTP — Context7 `/docs/howto/oauth`, fetched
  2026-11-24. Verify with a live docs query.
- opencode enables OAuth by default for remote servers and keeps tokens outside
  project config — OpenCode `mcp-servers.mdx` via Context7, plus the live
  working entry in `~/.config/opencode/opencode.json` (read 2026-11-24). Verify
  with `opencode mcp auth context7` and a query.
- Copilot CLI accepts a remote HTTP MCP entry in its user config and Context7
  supports `--copilot --oauth` — `https://context7.com/get-started.md` and
  `/docs/resources/all-clients`, fetched 2026-11-24. Verify on the machine.
- The two local configs are the source of truth for the entries to sync —
  `diff -u` against the source files, 2026-11-24. Verify with `chezmoi diff
  --source dotfiles` after the edit: neither file should show changes.
- `tests/test.sh:156-164` runs every `tests/**/*-test.sh` — read at
  `tests/test.sh`. Verify the new test runs in the full gate.
