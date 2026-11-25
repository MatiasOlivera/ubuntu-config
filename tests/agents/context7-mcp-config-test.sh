#!/usr/bin/env bash
#
# context7-mcp-config-test.sh — hermetic contract checks for the declarative
# Context7 MCP entries. Reads committed files only; no network or system changes.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILURES=0
URL="https://mcp.context7.com/mcp/oauth"

fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

output=$(python3 - "$ROOT" "$URL" 2>&1 <<'PY'
import json
import sys
from pathlib import Path

root, url = Path(sys.argv[1]), sys.argv[2]
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


opencode_path = "dotfiles/dot_config/opencode/opencode.json"
config = load(opencode_path)
if config is not None:
    servers = config.get("mcp", {}).get("servers", {})
    server = servers.get("context7")
    check(server is not None, "opencode: context7 entry exists")
    if server:
        check(server.get("type") == "remote", "opencode: remote server type")
        check(server.get("url") == url, "opencode: OAuth endpoint")
        check("headers" not in server, "opencode: no API-key headers")
        check("command" not in server, "opencode: no local stdio server")
    check("github" in servers, "opencode: GitHub MCP preserved")
    check("sofa" in servers, "opencode: Stack Overflow MCP preserved")
    playwright = servers.get("playwright", {})
    check(any("playwright" in arg for arg in playwright.get("command", [])),
          "opencode: Playwright MCP preserved")

copilot_path = "dotfiles/dot_copilot/mcp-config.json"
config = load(copilot_path)
if config is not None:
    servers = config.get("mcpServers", {})
    server = servers.get("context7")
    check(server is not None, "copilot: context7 entry exists")
    if server:
        check(server.get("type") == "http", "copilot: remote HTTP type")
        check(server.get("url") == url, "copilot: OAuth endpoint")
        check(server.get("tools") == ["query-docs", "resolve-library-id"],
              "copilot: explicit Context7 tools")
        check("headers" not in server, "copilot: no API-key headers")
        check("command" not in server, "copilot: no local stdio server")
    check("github" in servers, "copilot: GitHub MCP preserved")

for relative in (opencode_path, copilot_path):
    text = (root / relative).read_text() if (root / relative).is_file() else ""
    check("CONTEXT7_API_KEY" not in text, relative + ": no API key reference")
    check("YOUR_API_KEY" not in text, relative + ": no placeholder key")

sys.exit(1 if failures else 0)
PY
)
status=$?
printf '%s\n' "$output"
if [[ $status -eq 0 ]]; then pass "Context7 MCP config contracts"; else fail "Context7 MCP config contracts ($status)"; fi

for file in setup/install.sh setup/post-install.sh; do
	if grep -qEi 'context7|CONTEXT7_API_KEY|ctx7' "$ROOT/$file"; then
		fail "$file must not wire the docs MCP"
	else
		pass "$file has no Context7 wiring"
	fi
done

if [[ $FAILURES -gt 0 ]]; then
	printf '%d check(s) failed\n' "$FAILURES" >&2
	exit 1
fi
printf 'all Context7 MCP config checks passed\n'
