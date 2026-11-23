# Grafana MCP runbook (development only, repo-scoped)

The Grafana MCP is for agents working in **this** repository. Its entries live in
repo-scoped project configs (`opencode.json`, `.github/mcp.json`,
`.kilocode/mcp.json`); nothing is added to chezmoi, `install.sh` or
`post-install.sh`, so a fresh setup never installs it. Other repositories can opt
in with their own copy of the same config.

One shared Grafana service account with the `Editor` role serves all four
agents. Its token is local development configuration: store it in GNOME Keyring
only — no Bitwarden item and no `SECRETS_MAP` entry. Create the service account
in the local Grafana UI, then store the token once (stdin keeps it out of shell
history and process arguments):

```sh
printf 'Grafana service-account token: ' >&2
read -r -s TOKEN
printf '\n' >&2
printf '%s' "$TOKEN" | secret-tool store --label grafana-mcp \
  service grafana-mcp account service-account-token
unset TOKEN
```

In each new shell, before starting an agent, supply the URL and token. The
default URL is the local stack from #77; override it when a different instance
is intended:

```sh
export GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
export GRAFANA_SERVICE_ACCOUNT_TOKEN="$(secret-tool lookup service grafana-mcp account service-account-token 2>/dev/null)"
```

The configs pin `mcp-grafana==2.2.0` (the latest version published on PyPI, which
`uvx` resolves) and pass this explicit tool set, replacing
the upstream defaults:

```text
search,datasource,prometheus,loki,alerting,dashboard,tempo
```

It covers dashboards and alerts, Loki logs, Prometheus metrics and Tempo
traces. Write tools are enabled deliberately; unrelated categories (admin,
cloud, SQL, incident, on-call, …) are not exposed. Change the set in all three
configs together and record the new set here.

Verify each agent (start the Grafana stack first):

```sh
opencode mcp list            # expect: grafana
copilot mcp list             # expect: grafana workspace server
kilo mcp list                # expect: grafana project server
agy mcp list                 # expect: grafana enabled (after the wiring below)
```

### agy needs a literal URL and token (host-only)

agy has no environment-variable expansion, so its entry carries the real URL
and token and stays out of the repo (both deny-lists exclude `mcp_config.json`).
Run the helper script, which reads the token from the Keyring and writes the
file with mode `0600` (never pass the token as an argument):

```sh
python3 docs/runbooks/agy-grafana-mcp.py
agy mcp list  # expect: grafana enabled
```

The merge preserves sibling servers. Re-run the script after every token
rotation and after changing the tool set: unlike the file-configured agents,
agy does not follow the Keyring or the repository configs automatically.
