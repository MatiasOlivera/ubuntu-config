# plan.md - `106-grafana-mcp-development-agents`

## Architecture

Three repo-scoped MCP configs spawn the same pinned upstream server as a local
stdio process; the fourth agent uses a host-local file because it cannot expand
environment variables. No chezmoi dotfile, `install.sh` or `post-install.sh`
changes are part of this plan.

| Component | Change |
| --- | --- |
| `opencode.json` (existing) | Add Grafana MCP entry; keep permissions |
| `.github/mcp.json` (new) | Copilot CLI workspace MCP entry |
| `.kilocode/mcp.json` (new) | Kilo CLI project MCP entry |
| `docs/runbooks/grafana-mcp-runbook.md` (new) | Development-only setup and agy wiring |
| `docs/runbooks/agy-grafana-mcp.py` (new) | Host-local agy entry writer |
| `tests/agents/grafana-mcp-config-test.sh` (new) | Hermetic config contract test |

- Root `opencode.json` (existing): add `mcp.servers.grafana` with `type: "local"`,
  `command: ["uvx", "mcp-grafana==v2.3.0", "--enabled-tools=<list>"]` and
  `environment` using `{env:GRAFANA_URL}` / `{env:GRAFANA_SERVICE_ACCOUNT_TOKEN}`.
  Preserve the existing `permission.bash` deny-list.
- `.github/mcp.json` (new): Copilot CLI workspace config, auto-loaded per upstream
  changelog v1.0.61. `mcpServers.grafana` with `command: "uvx"`, `args` as above,
  and `env` using `${GRAFANA_URL}` / `${GRAFANA_SERVICE_ACCOUNT_TOKEN}`.
- `.kilocode/mcp.json` (new): Kilo CLI project-level MCP config per upstream docs.
  `mcpServers.grafana` with `command`, `args` and `env` using `{env:...}`.
- `docs/runbooks/grafana-mcp-runbook.md` (new): development-only
  Grafana MCP workflow — one-time keyring storage, shell exports, the recorded
  tool set, per-agent `mcp list` checks, and the host-local agy wiring (literal
  URL and token, `0600`, merge sibling servers, re-run after rotation) via
  `docs/runbooks/agy-grafana-mcp.py`. State explicitly that install-time
  provisioning is untouched.
- `tests/agents/grafana-mcp-config-test.sh` (new): hermetic contract test
  auto-discovered by `tests/test.sh` (`tests/test.sh:143-151`). Parses the three
  JSON configs; asserts the pinned version, explicit tool list, env placeholders
  and no literal token; asserts `install.sh`/`post-install.sh`/`dot_zshrc` have
  no Grafana MCP wiring; asserts the agy config path is still denied in both
  deny-lists (`.gitignore:64`, `dotfiles/.chezmoiignore:37`).

Data flow: the agent reads its project config, expands the environment
references, and starts `uvx mcp-grafana==v2.3.0` with `GRAFANA_URL` and
`GRAFANA_SERVICE_ACCOUNT_TOKEN`; tool calls go to the local Grafana instance.
For agy the runbook writes the same values literally into
`~/.gemini/config/mcp_config.json`, which both deny-lists already exclude, so
chezmoi never overwrites it.

Sequence: failing contract test → three configs → runbook → full gate → manual
machine verification.

## Data models

None. The change is configuration plus documentation; no persisted application
data or migration is involved.

## API contracts

Enabled tool categories (explicit list, replacing upstream defaults):
`search,datasource,prometheus,loki,alerting,dashboard,tempo`. This covers
dashboard search/inspection and updates, datasource discovery, Prometheus
metrics, Loki logs, alert-rule inspection and changes, and Tempo trace search
and retrieval. Write tools are deliberately enabled; categories outside this
list (admin, cloud, SQL, incident, on-call, etc.) are not exposed. The list is
recorded in the runbook and asserted by the contract test.

Per-agent environment syntax (load-bearing, verified from upstream docs):

| Agent | Config key | Expansion | Source |
| --- | --- | --- | --- |
| opencode | `mcp.servers.<name>.environment` | `{env:VAR}` | OpenCode MCP docs, `mcp-servers.mdx` (Context7 `/anomalyco/opencode`) |
| Copilot CLI | `mcpServers.<name>.env` | `${VAR}` | copilot-cli `changelog.md` v0.0.340 (Context7 `/github/copilot-cli`) |
| Kilo CLI | `mcpServers.<name>.env` | `{env:VAR}` | kilo docs `platforms/cli.md` and `automate/mcp/using-in-cli.md` (Context7 `/kilo-org/kilo`) |
| agy | `~/.gemini/config/mcp_config.json`, `mcpServers.<name>` | none — literal values | existing runbook pattern, `docs/runbooks/agent-credentials-runbook.md:115-152` |

Upstream server facts: v2.3.0 is the latest release (GitHub release API,
queried 2026-11-23); `--enabled-tools` replaces the default category set, which
includes `tempo` (upstream
`docs/sources/configure/command-line-flags.md`, "Configure tool categories").

Acceptance scenario mapping: opencode/Copilot/Kilo agent scenarios map to the
three configs and their tool categories; the agy scenario maps to the runbook
step; the write-access scenario maps to the recorded explicit category list;
the no-token and fresh-machine scenarios map to the contract test; the gate
scenario maps to `./tests/test.sh`.

## Decisions

None. This issue applies the stack decision in
`docs/decisions/0009-e2e-run-observability.md` and the credential policy in
`docs/decisions/0002-credential-storage.md`; the scope and tool-set choices are
recorded in `spec.md` and the runbook. No new MADR is warranted for a
development dependency.

## Risks

- The Editor-role identity is broad at the Grafana API level even though the
  tool set is explicit; the tool list, not RBAC, is the agent-facing boundary.
- The keyring token has no vault backup and is not synced automatically; the
  runbook covers manual rotation, including re-writing the agy host file.
- A pinned version can go stale; the contract test makes the bump a four-line
  change (three configs plus the test expectation).
- Config filenames and expansion rules differ by CLI version; the runbook's
  `mcp list` checks make a mismatch visible rather than silent.
- `uvx` fetches the package on first use; `uv` is the repository's chosen
  Python tool (`docs/language-package-managers.md`), and the first fetch only
  happens when an agent actually uses the server.

## Assumptions

- Latest upstream release v2.3.0 — GitHub release API, 2026-11-23; verify with
  `gh release view grafana/mcp-grafana`.
- Local Grafana at `http://localhost:3000` — `AGENTS.md` end-to-end
  observability section and `tests/observability/compose.yml`; verify by
  starting the stack.
- Tempo tools enabled by default — upstream command-line-flags reference;
  verify with `mcp-grafana --help`.
- `uv`/`uvx` available — `docs/language-package-managers.md`; verify with
  `uv --version`.
- Copilot CLI auto-loads `.github/mcp.json` — upstream changelog v1.0.61;
  verify with `copilot mcp list`.
- Kilo CLI accepts `.kilocode/mcp.json` as project MCP config — upstream
  `automate/mcp/using-in-cli.md`; verify with `kilo mcp list`.
