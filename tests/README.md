# Test suite

The tiers are cumulative: each adds isolation and runs only after the one below
it is green. `tests/test.sh` (Facade) is the single entry point for the static
and e2e tiers, and it also discovers every `*-test.sh` file under `tests/`.

## Test strategy

```mermaid
flowchart TD
    Change(["Change to setup or reports"]) --> Scoped["Scoped check: one test, bash -n, shellcheck"]
    Scoped -->|before review| Static["Static host checks: test.sh (Facade)"]
    Static --> Docker["Docker-isolated static: compose run"]
    Docker --> VM["Multipass e2e: test.sh --vm"]
    VM --> Keep["--keep: seed VM and leave it running"]
    Keep --> Reuse["--reuse: full re-run on seeded VM"]
    Reuse -->|edit setup scripts| Reuse
    Reuse --> Gate["full --reuse gate before PR"]
```

Scoped checks run while editing. The full gate runs before the first local
review, and again before a pull request only when review feedback changed code.
`--keep` and `--reuse` are valid only with `--vm`, and the per-worktree VM lock
allows one e2e run per checkout at a time. The host static tier sources library
scripts, so use the Docker-isolated tier for an untrusted checkout.
