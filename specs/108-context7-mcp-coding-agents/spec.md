# spec.md - `108-context7-mcp-coding-agents`

## Context

Issue #108 asks for current library documentation to be available to coding
agents working in **any** repository, set up automatically on a fresh machine.
Today agents answer library questions from training data or web search; this
repo already gives them GitHub and Stack Overflow docs sources, but no library
docs source.

Context7 provides that source through a remote MCP server with browser-based
OAuth sign-in and no API key. The change gives the two agents whose config is
already deployed to fresh machines — opencode and GitHub Copilot CLI — a
Context7 entry, while leaving their existing MCP entries intact.

Decisions settled with the issue owner:

- Scope is opencode and Copilot CLI only. Cursor, VS Code, agy and Kilo are out
  of scope: they have no declaratively deployed MCP config here, and agy's host
  config is deliberately excluded from both deny-lists by #106.
- The entry lives in the global, chezmoi-managed agent config so a fresh-machine
  install provides it in every repository. It is not duplicated in repo-scoped
  config, so no environment fact has two owners.
- "Without manual per-agent configuration" means the config is deployed
  automatically; OAuth sign-in remains a one-time, per-agent browser action,
  because upstream docs confirm most MCP clients do not authenticate
  automatically and the issue forbids committing any credential.
- No API key, token or value derived from one is committed. No setup script
  runs an unpinned third-party setup command to produce the config.
- The entries are synced from the ones already working on this machine, not
  invented: the opencode source gains Context7 and the local-only `playwright`
  entry, so a re-apply removes no existing capability. Copilot's Context7 entry
  lists `query-docs` and `resolve-library-id` explicitly instead of the current
  wildcard, per upstream docs.

## User stories

- As a maintainer setting up a fresh machine, I want Context7 ready in my
  coding agents after the normal install so that I do not configure each agent
  by hand.
- As a maintainer working in any repository, I want to ask my agent for current
  library docs so that I stop relying on stale training data.
- As a maintainer, I want to sign in once with my Context7 account in the
  browser so that no API key or token is stored in the public repo.
- As a maintainer, I want the GitHub, Stack Overflow and local Playwright MCP
  entries to keep working so that this change does not take capabilities away.
- As a maintainer of a public repository, I want a hermetic check of the
  deployed config shape so that regressions are caught without network access.

## Acceptance criteria (BDD)

```gherkin
Scenario: fresh machine gets the docs source without per-agent setup
  Given a fresh Ubuntu machine being set up with this repository's documented install
  When the install finishes and the maintainer starts opencode and Copilot CLI
  Then both agents list a Context7 MCP server without any manual config-file editing
  And the maintainer's GitHub and Stack Overflow MCP entries are still listed
  And the maintainer's Playwright MCP entry is still listed in opencode

Scenario: opencode answers a library docs question
  Given the maintainer has completed the one-time Context7 browser sign-in in opencode
  When the maintainer asks opencode to resolve a library name and query its docs
  Then opencode returns a library ID and current documentation through the Context7 server

Scenario: Copilot CLI answers a library docs question
  Given the maintainer has completed the one-time Context7 browser sign-in in Copilot CLI
  When the maintainer asks Copilot CLI to query documentation for a library
  Then the answer comes from the Context7 server in the same session

Scenario: sign-in is browser based and no credential is committed
  Given the public repository and a configured development machine
  When the maintainer signs in through each agent's OAuth flow
  Then no API key, token or token-derived value appears in any tracked file
  And no API key is requested from the maintainer

Scenario: sign-in is still required after a fresh install
  Given a freshly installed machine where nobody has signed in to Context7
  When the maintainer asks an agent for library docs before authenticating
  Then the agent surfaces the normal authentication prompt or reports the server as pending
  And it does not fall back to asking for an API key

Scenario: reapplying dotfiles keeps every existing agent entry
  Given this machine's opencode and Copilot CLI configs contain Context7, GitHub, Stack Overflow and Playwright entries
  When the maintainer re-applies the dotfiles
  Then none of those entries is removed from either agent's config

Scenario: verification gate stays green
  Given the completed change
  When the maintainer runs "./tests/test.sh"
  Then the command exits zero
```

## Constraints

- [ ] Context7 uses only the remote OAuth endpoint; no local stdio server and
      no API-key authentication path is configured.
- [ ] Configuration is declarative and deployed by chezmoi; `install.sh` and
      `post-install.sh` gain no Context7 step and no remote setup CLI call.
- [ ] Existing GitHub and Stack Overflow MCP entries stay unchanged and
      available in both agents; the local Playwright entry is retained too.
- [ ] Copilot's Context7 entry enables exactly `query-docs` and
      `resolve-library-id`, matching upstream's documented tool set.
- [ ] Scope is opencode and Copilot CLI; no new agent install, dotfile or
      deny-list change is required.
- [ ] No credential, API key or token value is committed to the public repo.
- [ ] `./tests/test.sh` stays green, including a hermetic config contract check.

## Assumptions

- The Context7 OAuth endpoint is `https://mcp.context7.com/mcp/oauth`, a remote
  streamable-HTTP server; OAuth works only over remote HTTP, never local stdio
  (Context7 `/docs/howto/oauth` and `/docs/resources/all-clients`, fetched
  2026-11-24). Verify with a live `resolve-library-id` / `query-docs` call.
- opencode enables OAuth by default for remote servers and stores tokens
  outside project config (OpenCode `mcp-servers.mdx`, via Context7). The entry
  `{"type":"remote","url":"https://mcp.context7.com/mcp/oauth"}` is already
  working in the development environment used to write this spec. Verify with
  `opencode mcp auth context7` and a docs query.
- Copilot CLI can configure a remote HTTP MCP server in its user config, and
  Context7 lists it as a supported OAuth setup client (`--copilot` in
  `https://context7.com/get-started.md`, fetched 2026-11-24). Its OAuth flow is
  **provisional** until verified on the machine; verify with `copilot mcp list`
  and a docs query after sign-in.
- Most clients do not authenticate automatically after an OAuth entry is added
  (Context7 `/docs/howto/oauth`, fetched 2026-11-24). Verify during the manual
  machine check and document the one-time step.
- The local machine's Context7 entries (opencode `type: remote` at the OAuth
  URL; Copilot CLI `type: http` at the OAuth URL with `tools: ["*"]`) are the
  working source of truth, read 2026-11-24; verify by applying the updated
  source and confirming both agents still list the server. Narrowing Copilot's
  tools to the two documented names is per Context7's all-clients docs; verify
  with `copilot mcp list` and a docs query.
- Cursor, VS Code, agy and Kilo need no change for this issue; #106's spec and
  the current deny-lists record why agy is excluded from declarative config.
