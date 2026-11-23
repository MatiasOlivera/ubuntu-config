#!/usr/bin/env bash
#
# grafana-mcp-config-test.sh — hermetic contract checks for the development-only
# Grafana MCP configs. Reads committed files only; no network or system changes.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILURES=0
VERSION="mcp-grafana==v2.3.0"
TOOLS="search,datasource,prometheus,loki,alerting,dashboard,tempo"

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

output=$(python3 - "$ROOT" "$VERSION" "$TOOLS" 2>&1 <<'PY'
import json
import sys
from pathlib import Path

root, version, tools = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
failures = 0


def check(ok, message):
    global failures
    if ok:
        print("ok: " + message)
    else:
        print("FAIL: " + message, file=sys.stderr)
        failures += 1


def load(relative):
    path = root / relative
    if not path.is_file():
        check(False, relative + " exists")
        return None
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        check(False, relative + " parses (" + str(exc) + ")")
        return None


def tool_arg(args):
    prefix = "--enabled-tools="
    return next((arg for arg in args if arg.startswith(prefix)), None)


config = load("opencode.json")
if config is not None:
    server = config.get("mcp", {}).get("servers", {}).get("grafana")
    check(server is not None, "opencode: mcp.servers.grafana exists")
    if server:
        command = server.get("command", [])
        check(server.get("type") == "local", "opencode: local server type")
        check(command[:2] == ["uvx", version], "opencode: pinned uvx command")
        check(tool_arg(command[2:]) == "--enabled-tools=" + tools,
              "opencode: explicit tool set")
        environment = server.get("environment", {})
        check(environment.get("GRAFANA_URL") == "{env:GRAFANA_URL}",
              "opencode: URL env reference")
        check(environment.get("GRAFANA_SERVICE_ACCOUNT_TOKEN")
              == "{env:GRAFANA_SERVICE_ACCOUNT_TOKEN}",
              "opencode: token env reference")

config = load(".github/mcp.json")
if config is not None:
    server = config.get("mcpServers", {}).get("grafana")
    check(server is not None, "copilot: mcpServers.grafana exists")
    if server:
        args = server.get("args", [])
        check(server.get("command") == "uvx", "copilot: uvx command")
        check(args[:1] == [version], "copilot: pinned version")
        check(tool_arg(args[1:]) == "--enabled-tools=" + tools,
              "copilot: explicit tool set")
        environment = server.get("env", {})
        check(environment.get("GRAFANA_URL") == "${GRAFANA_URL}",
              "copilot: URL env reference")
        check(environment.get("GRAFANA_SERVICE_ACCOUNT_TOKEN")
              == "${GRAFANA_SERVICE_ACCOUNT_TOKEN}",
              "copilot: token env reference")

config = load(".kilocode/mcp.json")
if config is not None:
    server = config.get("mcpServers", {}).get("grafana")
    check(server is not None, "kilo: mcpServers.grafana exists")
    if server:
        args = server.get("args", [])
        check(server.get("command") == "uvx", "kilo: uvx command")
        check(args[:1] == [version], "kilo: pinned version")
        check(tool_arg(args[1:]) == "--enabled-tools=" + tools,
              "kilo: explicit tool set")
        environment = server.get("env", {})
        check(environment.get("GRAFANA_URL") == "{env:GRAFANA_URL}",
              "kilo: URL env reference")
        check(environment.get("GRAFANA_SERVICE_ACCOUNT_TOKEN")
              == "{env:GRAFANA_SERVICE_ACCOUNT_TOKEN}",
              "kilo: token env reference")

for relative in ("opencode.json", ".github/mcp.json", ".kilocode/mcp.json"):
    path = root / relative
    text = path.read_text() if path.is_file() else ""
    check("glsa_" not in text, relative + ": no literal Grafana token")

sys.exit(1 if failures else 0)
PY
)
status=$?
printf '%s\n' "$output"
if [[ $status -eq 0 ]]; then pass "grafana MCP config contracts"; else fail "grafana MCP config contracts ($status)"; fi

for file in setup/install.sh setup/post-install.sh dotfiles/dot_zshrc; do
	if grep -qE 'mcp-grafana|GRAFANA_SERVICE_ACCOUNT_TOKEN|GRAFANA_URL' "$ROOT/$file"; then
		fail "$file must not wire the development MCP"
	else
		pass "$file has no Grafana MCP wiring"
	fi
done

if grep -qF 'dotfiles/dot_gemini/config/mcp_config.json' "$ROOT/.gitignore"; then
	pass "commit deny-list still excludes agy MCP config"
else
	fail "commit deny-list lost the agy MCP config entry"
fi
if grep -qF '.gemini/config/mcp_config.json' "$ROOT/dotfiles/.chezmoiignore"; then
	pass "deploy deny-list still excludes agy MCP config"
else
	fail "deploy deny-list lost the agy MCP config entry"
fi

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all grafana MCP config checks passed\n'
