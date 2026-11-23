#!/usr/bin/env python3
"""Write the host-local agy Grafana MCP entry from the GNOME Keyring token.

Run from anywhere: python3 docs/runbooks/agy-grafana-mcp.py
The token is read from the keyring, never passed as an argument. The target
config is excluded from both the commit and deploy deny-lists.
"""

import json
import os
import subprocess
from pathlib import Path

cfg_path = Path.home() / ".gemini/config/mcp_config.json"
token = subprocess.run(
    ["secret-tool", "lookup", "service", "grafana-mcp",
     "account", "service-account-token"],
    capture_output=True, text=True, check=True).stdout.strip()
if not token:
    raise SystemExit("no Grafana token in keyring")

cfg = json.loads(cfg_path.read_text()) if cfg_path.exists() else {}
cfg.setdefault("mcpServers", {})["grafana"] = {
    "command": "uvx",
    "args": [
        "mcp-grafana==v2.3.0",
        "--enabled-tools=search,datasource,prometheus,loki,alerting,dashboard,tempo",
    ],
    "env": {
        "GRAFANA_URL": os.environ.get("GRAFANA_URL", "http://localhost:3000"),
        "GRAFANA_SERVICE_ACCOUNT_TOKEN": token,
    },
    "disabled": False,
}

cfg_path.parent.mkdir(parents=True, exist_ok=True)
# 0600 at creation: write_text + chmod afterwards leaves a window where the
# token is readable under a permissive umask (or forever if chmod never runs).
fd = os.open(cfg_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    f.write(json.dumps(cfg, indent=2) + "\n")
os.chmod(cfg_path, 0o600)  # also tightens a pre-existing lax file
