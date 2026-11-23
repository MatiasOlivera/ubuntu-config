# spec.md - `106-grafana-mcp-development-agents`

## Context

A maintainer debugging a verification run from this repo cannot inspect the
observability data from the coding agent session: the agents carry GitHub and
Stack Overflow MCPs, but no observability tools. Inspecting logs, metrics and
traces means leaving the session.

This change gives the four development agents (opencode, Copilot CLI, Kilo and
agy) direct access to the Grafana stack through one upstream `grafana/mcp-grafana`
server. The Grafana URL and token are development-machine configuration; the
public repository holds no token value.

The stack is used from several repositories, but this MCP is only for agents
developing **this** repository. It must therefore live in repo-scoped project
configuration, not in chezmoi home dotfiles that `install.sh` deploys to a
fresh machine. Other repositories can opt in with their own copy; the
credential stays on the machine, not in the config.

Design decisions settled with the issue owner:

- One shared service account with the Grafana `Editor` role serves all four
  agents. Write tools stay enabled, but the enabled tool set is explicit and
  recorded so access is deliberate and scoped, not an unexamined default.
- The token is stored only in GNOME Keyring. Bitwarden and `credential-sync`
  are not involved: this is a local development credential, not a shared one.
- The Grafana URL and token reach the three file-configured agents through
  environment references in each agent's own config syntax. agy cannot expand
  environment variables, so its entry is written to a host-local config that
  is excluded from both deny-lists, by a documented manual step — never by
  `install.sh`.
- `uvx` runs a pinned `mcp-grafana==v2.3.0` on every agent, and a small hermetic
  test checks the committed configs for the expected shape and the absence of
  a token value.
- One Grafana MCP is enough: its Tempo tools (`search_tempo_traces`,
  `get_tempo_trace`, `query_tempo_metrics`, …) are enabled by default, so no
  second Tempo MCP is needed.

## User stories

- As a maintainer debugging an e2e run from this repo, I want to ask my coding
  agent for a failed app's logs, timing and metrics so that I do not have to
  leave the session.
- As a maintainer, I want to inspect dashboards and alerts from the same
  session so that investigating a run does not break my workflow.
- As a maintainer, I want the enabled Grafana tool set recorded so that I know
  exactly what the agents can do and why.
- As a maintainer of a public repository, I want the Grafana URL and token
  supplied by the development machine only so that no credential is committed,
  and I want fresh machines untouched by this development-only tooling.

## Acceptance criteria (BDD)

```gherkin
Scenario: opencode can inspect a failed run
  Given the #77 Grafana stack is running and the development machine supplies the Grafana URL and token
  When the maintainer starts opencode in this repo and asks for a failed app's logs
  Then the agent returns the relevant log lines through the Grafana MCP without leaving the session

Scenario: Copilot CLI can inspect dashboards and alerts
  Given the Grafana MCP is configured for Copilot CLI in this repository
  When the maintainer asks the agent to list dashboards and alert rules
  Then the agent returns the dashboards and alert rules from the running Grafana instance

Scenario: Kilo can query traces from the same server
  Given the #77 stack has Tempo trace data and the Grafana MCP is configured for Kilo in this repository
  When the maintainer asks the agent to find a trace by ID
  Then the agent returns the trace through the single Grafana MCP, with no second Tempo server configured

Scenario: agy is wired from a host-local config
  Given agy cannot expand environment variables in its MCP config
  When the maintainer follows the documented host-only wiring and runs "agy mcp list"
  Then the Grafana server is listed and no token value exists in any tracked file

Scenario: write access is deliberate and recorded
  Given the Grafana MCP is connected with the recorded tool set
  When the maintainer asks an agent which Grafana tools are available
  Then the listed tools match the recorded categories, including dashboard and alert write tools
  And no unrelated categories are exposed

Scenario: no credential is committed
  Given this public repository and the configured development machine
  When the maintainer greps all tracked files for the Grafana token value
  Then no token value is found; only environment references appear

Scenario: fresh machines are unaffected
  Given a fresh machine being set up with install.sh
  When the install finishes
  Then no Grafana MCP entry has been deployed by the setup

Scenario: verification gate stays green
  Given the completed change
  When the maintainer runs "./tests/test.sh"
  Then the command exits zero
```

## Constraints

- [ ] One upstream `grafana/mcp-grafana` server serves all four agents; no
      separate Tempo MCP is added.
- [ ] Grafana URL and token are development-machine configuration only; no
      token value is committed, and Bitwarden/`credential-sync` are untouched.
- [ ] The enabled tool set is recorded; write access is enabled deliberately
      rather than inherited from an unexamined default.
- [ ] The choice reflects #77's outcome: the local stack URL, a service account
      with the needed permissions, and tools for logs, metrics, traces,
      dashboards and alerts.
- [ ] Configuration is repo-scoped. No chezmoi dotfile, `install.sh` or
      `post-install.sh` change is part of this issue.
- [ ] `./tests/test.sh` stays green.

## Assumptions

- The latest upstream release is v2.3.0 (GitHub release API, queried
  2026-11-23); verify with `gh release view grafana/mcp-grafana` before pinning.
- The local Grafana endpoint is `http://localhost:3000` (AGENTS.md and
  `tests/observability/compose.yml`); verify by starting the stack.
- Tempo tools are enabled by default (upstream command-line-flags reference);
  verify with `mcp-grafana --help` after the server is installed.
- `uv`/`uvx` is available on the development machine
  (`docs/language-package-managers.md`); verify with `uv --version`.
- Copilot CLI auto-loads `.github/mcp.json` (changelog v1.0.61) and Kilo CLI
  supports `.kilocode/mcp.json` as project-level MCP config (current Kilo docs);
  verify with `copilot mcp list` and `kilo mcp list` on the machine.
