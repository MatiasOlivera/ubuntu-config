# tasks.md - `106-grafana-mcp-development-agents`

> Atomic, dependency-ordered, each independently verifiable.

| ID  | Done | Task | Depends on | Type      | Verification |
| --- | ---- | ---- | ---------- | --------- | ------------ |
| 1   | [x]  | Add `tests/agents/grafana-mcp-config-test.sh` asserting the three configs' shape, pinned version, explicit tool list, env placeholders, no token value, no setup/chezmoi wiring, and intact agy deny-list entries | - | Automated | Run `bash tests/agents/grafana-mcp-config-test.sh` — fails while configs are absent (red) |
| 2   | [ ]  | Add `mcp.servers.grafana` to root `opencode.json` with the pinned command, explicit tool list and `{env:...}` references; preserve existing permissions | 1 | Automated | `bash tests/agents/grafana-mcp-config-test.sh` passes its opencode assertions (green) |
| 3   | [ ]  | Add `.github/mcp.json` with the Copilot CLI `mcpServers.grafana` entry and `${...}` references | 1 | Automated | `bash tests/agents/grafana-mcp-config-test.sh` passes its Copilot assertions |
| 4   | [ ]  | Add `.kilocode/mcp.json` with the Kilo CLI `mcpServers.grafana` entry and `{env:...}` references | 1 | Automated | `bash tests/agents/grafana-mcp-config-test.sh` passes its Kilo assertions |
| 5   | [ ]  | Add a development-only Grafana MCP section to `docs/runbooks/agent-credentials-runbook.md`: keyring-only token, shell exports, recorded tool set, per-agent `mcp list` checks, host-local agy wiring and rotation, explicit note that install-time provisioning is untouched | 4 | Manual | Read the section against `plan.md`: all five items present, no `install.sh`/`credential-sync` change described |
| 6   | [ ]  | Run the full static gate | 5 | Automated | `./tests/test.sh` exits 0 |
| 7   | [ ]  | Verify on the development machine: start the stack, export the two variables, confirm `opencode mcp list`, `copilot mcp list`, `kilo mcp list` and `agy mcp list` show `grafana`, and ask one agent for a trace from a recorded run | 6 | Manual | All four commands list `grafana`; one trace query returns data; no token in tracked files |
