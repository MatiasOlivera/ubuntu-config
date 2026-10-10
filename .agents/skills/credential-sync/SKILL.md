---
name: credential-sync
description: Bridge and rotate agent credentials between Bitwarden and GNOME Keyring. Use when an MCP 401 appears, a credential env var is empty, `bw get` answers Not found, a token needs rotation, or a new agent secret must be added to the sync map.
---

# Credential sync

Standing rules for every credential that coding-agent tooling consumes on
this machine. The full manual procedure lives in the runbook at
`docs/runbooks/agent-credentials-runbook.md`; this skill states the rules
an agent MUST obey when diagnosing or changing anything credential-related.

## When to use

- MCP authentication failures (`401 Unauthorized`) or empty credential env
  vars in a fresh shell.
- `bw get` answering `Not found` for an item that exists in the browser
  extension or web vault.
- Rotating a credential (expiry or leak suspicion).
- Adding a new secret for agent tooling (new Bitwarden item, keyring entry,
  or consumer).

## Instructions

1. MUST diagnose before changing: `401` means expired/revoked or stale
   (deleted provider-side, never re-synced) — rotate, don't rewire configs;
   `Not found` means the CLI cache is stale — MUST run `bw sync` before
   anything else; an env var empty in every shell means the login keyring
   isn't unlocking — MUST check unlock before touching stored values.
2. MUST treat `SECRETS_MAP` at the top of
   `setup/security/credential-sync.sh` as the registry of covered secrets.
   MUST add new secrets there. MUST NOT keep a per-service list in prose —
   it would be a second source of truth churning on every addition.
3. MUST keep the hybrid rule from
   `docs/decisions/0002-credential-storage.md`: Bitwarden holds the durable
   copy, GNOME Keyring holds the runtime copy. MUST NOT commit secret bytes
   anywhere in the repo; item names, service/account names, and env var
   names are safe to commit, values never are.
4. MUST bridge secrets via stdin (`bw get password <item> | secret-tool
   store ...`), never as command arguments, so values stay out of shell
   history. SHOULD prefer the re-runnable script over the manual path.
5. MUST rotate with `--force` (`credential-sync.sh --force [item ...]`):
   a plain re-run skips entries already stored, so without the flag a
   revoked value stays in place. MUST re-run any host-only literal-token
   wiring after rotation — it does not follow the Keyring automatically.
6. MUST verify after every change with the consumer's own check (runbook's
   worked example) in a new shell, and MUST keep `tests/test.sh` green when
   touching the script (see the `run-tests` skill for the loop).
