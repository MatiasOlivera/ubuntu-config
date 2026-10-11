# Agent credentials runbook (vault → keyring bridge)

> Rule: `docs/decisions/0002-credential-storage.md` (hybrid vault + keyring).
> This repo holds install steps and lookup snippets only — never secret values.

## Which secrets this covers

Every secret in `SECRETS_MAP` at the top of
`setup/security/credential-sync.sh` — that table is the registry. This
runbook names no per-service list on purpose: a prose list would be a
second source of truth churning on every addition. To see what's covered,
run the script — its `present:`/`pending:` output is the live list.
Per-consumer config wiring stays in chezmoi-managed files, never here.

## Bridge a new secret (manual path)

1. Create the credential on the provider; save it in a new Bitwarden item
   (type Login is fine, secret in the password field). This is the durable
   copy: sync, backup, and the source for rotation and future machines.
   Provider-side creation can never be automated — copy the value once.
2. Bridge it into GNOME Keyring — easiest via the sync script (re-runnable,
   skips what's already stored):

   ```sh
   bash setup/security/credential-sync.sh
   ```

   Same thing by hand (secret travels via stdin — never as an argument,
   so it stays out of history). Capture the unlock session first: without
   it, `bw sync` and `bw get` run against a locked vault and fail:

   ```sh
   bw login
   export BW_SESSION="$(bw unlock --raw)"
   bw sync
   ITEM=<bitwarden-item> SERVICE=<keyring-service> ACCOUNT=<keyring-account>
   SECRET="$(bw get password "$ITEM")" && [ -n "$SECRET" ] \
     && printf '%s' "$SECRET" | secret-tool store --label "$ITEM" service "$SERVICE" account "$ACCOUNT" \
     || echo "bridge failed for $ITEM" >&2
   bw lock && bw logout
   unset BW_SESSION SECRET
   ```

   The read-then-store order matters: a failed read must never reach the
   keyring, since empty stdin stores an empty value and reports success.

   Step 3 is load-bearing: extension/web edits live server-side and the
   CLI cache is stale until sync — without it, `bw get` answers
   `Not found` for items you just created in the browser. The script
   syncs fail-closed before storing, so the scripted path never hits this.
3. Confirm it's stored (prints the secret, so run privately):

   ```sh
   secret-tool lookup service <service> account <account> >/dev/null && echo OK
   ```

4. Open a new shell and check the consumer's env var is populated (each
   consumer documents its own var name; locked-keyring sessions such as
   SSH without unlock leave it empty — agents will report auth failure
   instead of leaking anything).

## Rotation (on expiry or any leak suspicion)

1. Create the new credential, update the Bitwarden item.
2. Re-sync the Keyring with `bash setup/security/credential-sync.sh --force
   <item>` — a plain re-run skips entries already stored, so without the
   flag the revoked value stays. Re-run any host-only literal-token wiring
   the consumer needs (it does not follow the Keyring automatically).
3. Open a new shell, re-run that consumer's verification. Revoke the old
   credential on the provider side.

## Troubleshooting

- `bw get → Not found` right after creating the item in the browser
  extension: run `bw sync` first, then retry.
- `401 Unauthorized`: credential expired or revoked — rotate. A stored
  value can still be stale (deleted provider-side, never re-synced):
  re-bridge with `--force`, then check the new value against the
  provider before blaming client configs.
- Empty env var in every shell: login keyring isn't unlocking at login —
  check GNOME keyring autostart; as a workaround run one
  `secret-tool lookup ...` to trigger unlock, then open a new shell.

## Worked example: GitHub MCP for coding agents (read-only)

Coding agents (opencode, `agy`, Copilot CLI) get **read-only** GitHub access via the hosted
MCP server. Two layers enforce it: a read-only fine-grained PAT, and the `/readonly`
server URL that hides write tools from the model. For writes, use `gh` yourself.

Create the PAT (fine-grained — classic PATs have no true read-only repo
scope): [github.com/settings/personal-access-tokens/new](https://github.com/settings/personal-access-tokens/new).

- Token name: `coding-agents-readonly`
- Expiration: 90 days (or shorter)
- Repository access: all repositories (read-only), or selected repos if you prefer
- Repository permissions: **Contents: Read**, **Issues: Read**, **Pull requests: Read**,
  **Actions: Read** (optional, CI visibility). Nothing set to write. Metadata read is automatic.
- Account permissions: none.

Copy the token once — GitHub never shows it again. Then Bitwarden item
`github-mcp-pat` → bridge per above with
`service github-mcp account personal-access-token` → env var
`GITHUB_PAT_FOR_CODING_AGENTS` (shell fills it from the Keyring at startup).

Verify each agent:

```sh
opencode mcp list            # expect: github, connected
opencode mcp debug github    # auth/connectivity diagnostics on failure
agy mcp list                 # expect: github enabled
copilot mcp list             # expect: github + builtin github-mcp-server
copilot mcp get github       # check URL ends /readonly, no literal token in file
```

### agy needs a literal token (host-only)

Upstream agy has no env-var expansion — `${...}` is sent literally and the server
answers `initialize: Bad Request` (verified). So agy's entry carries a literal
PAT and stays out of the repo (both deny-lists exclude
`mcp_config.json` — see comments there). Write it with a script that reads
the token from the Keyring — never pass it via `--header` or any other
command-line argument, where it would be visible in process arguments:

```sh
python3 - <<'EOF'
import json, os, subprocess
from pathlib import Path
cfg_path = Path.home() / ".gemini/config/mcp_config.json"
token = subprocess.run(
    ["secret-tool", "lookup", "service", "github-mcp",
     "account", "personal-access-token"],
    capture_output=True, text=True, check=True).stdout.strip()
cfg = json.loads(cfg_path.read_text()) if cfg_path.exists() else {}
cfg.setdefault("mcpServers", {})["github"] = {
    "serverUrl": "https://api.githubcopilot.com/mcp/readonly",
    "headers": {"Authorization": "Bearer " + token},
    "disabled": False,
}
cfg_path.parent.mkdir(parents=True, exist_ok=True)
# 0600 at creation: write_text + chmod afterwards leaves a window where the
# PAT is readable under a permissive umask (or forever if chmod never runs).
fd = os.open(cfg_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    f.write(json.dumps(cfg, indent=2) + "\n")
os.chmod(cfg_path, 0o600)  # also tightens a pre-existing lax file
EOF
agy mcp list  # expect: github enabled
```

The heredoc keeps the token out of shell history and process arguments
alike, and the merge preserves sibling servers. Re-run this after every PAT
rotation — unlike the other two agents, agy does not follow the Keyring automatically.

Safety check — ask any agent: *"Create a test issue in <repo> titled 'mcp write test'"*.
Expected: a permission error. If an issue actually appears, the PAT has write scope:
revoke it on github.com and redo the PAT step.
