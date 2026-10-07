# GitHub MCP for coding agents (read-only)

Coding agents (opencode, `agy`, Copilot CLI) get **read-only** GitHub access via the hosted
MCP server. Two layers enforce it: a read-only fine-grained PAT, and the `/readonly`
server URL that hides write tools from the model. For writes, use `gh` yourself.

Related: credential-storage rule in
`docs/decisions/0002-credential-storage.md`.

## Quick start (fresh install)

1. Run `./setup/install.sh`, then `./setup/post-install.sh` in a new shell — installs
   opencode + Copilot + `libsecret-tools` + Bitwarden CLI, then agy + shell setup,
   and deploys configs.
2. Do manual steps 1–3 below (PAT creation can never be automated).
3. Verify with 4.

## What `install.sh` automates vs. what you do

| Step | Who |
| ---- | --- |
| Install `libsecret-tools`, Bitwarden CLI, opencode + Copilot (agy via `post-install.sh`) | `install.sh` |
| Deploy opencode + Copilot MCP configs + shell lookup snippet (agy is host-only, see 4) | chezmoi via `install.sh` |
| 1 Create the PAT, 2 store in Bitwarden, 3 bridge to Keyring | **you**, below |
| 4 Verify | **you**, below |

## 1 Create a read-only fine-grained PAT

Classic PATs have no true read-only repo scope (`repo` grants write), so this must be
**fine-grained**: [github.com/settings/personal-access-tokens/new](https://github.com/settings/personal-access-tokens/new).

- Token name: `coding-agents-readonly`
- Expiration: 90 days (or shorter)
- Repository access: all repositories (read-only), or selected repos if you prefer
- Repository permissions: **Contents: Read**, **Issues: Read**, **Pull requests: Read**,
  **Actions: Read** (optional, CI visibility). Nothing set to write. Metadata read is automatic.
- Account permissions: none.

Copy the token once — GitHub never shows it again. If you lost it before 2, delete it and start over.

## 2 Save the PAT in Bitwarden

Create item `github-mcp-pat` (type Login is fine) and paste the PAT in the password field.
This is the durable copy: sync, backup, and the source for rotation and future machines.

## 3 Bridge the PAT into GNOME Keyring

The agents read env var `GITHUB_PAT_FOR_CODING_AGENTS`, which your shell fills from the
Keyring at startup. Copy it there once — easiest via the sync script (re-runnable,
skips what's already stored):

```sh
bash setup/security/credential-sync.sh
```

Same thing by hand (secret travels via stdin — never as an argument,
so it stays out of history):

```sh
bw login && bw unlock
bw get password github-mcp-pat | secret-tool store --label "GitHub MCP PAT" service github-mcp account personal-access-token
bw lock && bw logout
```

Confirm it's stored (prints the token, so run privately):

```sh
secret-tool lookup service github-mcp account personal-access-token >/dev/null && echo OK
```

Open a new shell and check the env var is populated:

```sh
[ -n "$GITHUB_PAT_FOR_CODING_AGENTS" ] && echo OK || echo "keyring locked or empty"
```

Locked-keyring sessions (SSH without unlock) leave the var empty — agents will report auth
failure instead of leaking anything. Unlock the login keyring and open a new shell.

## 4 Verify each agent

```sh
opencode mcp list            # expect: github, connected
opencode mcp debug github    # auth/connectivity diagnostics on failure
agy mcp list                 # expect: github enabled
copilot mcp list             # expect: github + builtin github-mcp-server
copilot mcp get github       # check URL ends /readonly, no literal token in file
```

### agy needs a literal token (host-only)

Upstream agy has no env-var expansion — `${...}` is sent literally and the server
answers `initialize: Bad Request` (verified). So agy's entry is set with a literal
PAT via the CLI and stays out of the repo (both deny-lists exclude
`mcp_config.json` — see comments there):

```sh
agy mcp add --header "Authorization: Bearer $(secret-tool lookup service github-mcp account personal-access-token)" github https://api.githubcopilot.com/mcp/readonly
chmod 600 ~/.gemini/config/mcp_config.json
```

The `$(...)` keeps the token out of shell history. Re-run this after every PAT
rotation — unlike the other two agents, agy does not follow the Keyring automatically.

Safety check — ask any agent: *"Create a test issue in <repo> titled 'mcp write test'"*.
Expected: a permission error. If an issue actually appears, the PAT has write scope:
revoke it on github.com and redo 1.

## Rotation (every ~90 days or on any leak suspicion)

1. Create the new PAT (1), update the Bitwarden item (2).
2. Re-sync the Keyring with `bash setup/security/credential-sync.sh --force
   github-mcp-pat` — a plain re-run skips entries already stored, so without
   the flag the revoked token stays. Plus the agy host-only add in 4 (agy's
   literal token does not follow rotation).
3. Open a new shell, re-run 4. Revoke the old PAT on github.com.

## Troubleshooting

- `401 Unauthorized`: PAT expired or revoked — rotate. A stored value can still
  be stale (deleted on GitHub, never re-synced): re-bridge with
  `credential-sync.sh --force`, then check the new token against
  `https://api.github.com/user` (want `200`) before blaming client configs.
- `agy` shows `initialize: Bad Request`: the header holds a placeholder instead of a
  literal token — re-run the host-only `agy mcp add` in 4, then restart the agent.
- `copilot` stored a literal token instead of the env reference: edit
  `~/.copilot/mcp-config.json` to use the `${...}` form, then restart the CLI.
- Empty env var in every shell: login keyring isn't unlocking at login — check
  GNOME keyring autostart; as a workaround run `secret-tool lookup ...` once to trigger unlock.
- Write tools visible to the model: config URL must end in `/readonly`; fix and restart the agent.
