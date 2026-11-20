# tasks.md - `49-ollama-publisher-integrity-exception`

| ID | Done | Task | Depends on | Type      | Verification |
| --- | ---- | ---- | ---------- | --------- | ------------ |
| 1 | [ ] | Widen the register scope sentence and add the Ollama row with review date, GPU/service rationale, published-checksum caveat, and accepted risk | - | Manual | `git diff --check`; row fills every column and the README Security link still resolves |
| 2 | [ ] | Confirm the Ollama install step is unchanged and the verify chain is green | 1 | Manual | `git diff -- setup/development/ollama.sh` is empty; `./tests/test.sh` passes; no new `docs/decisions/0008-*` file |

Verification rows map to the spec scenarios: task 2 covers "fresh installation",
"supported GPU setup", and "already installed skips without network" by leaving
the upstream install path byte-for-byte unchanged; task 1 covers "accepted
integrity exception is documented".
