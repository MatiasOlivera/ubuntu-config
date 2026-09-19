---
name: run-tests
description: Use when running or iterating on this repo's checks while changing setup — static ./tests/test.sh, docker-isolated compose check, Multipass e2e (--vm/--reuse/--keep), verifying an install change, choosing VM flags.
---

# Run and iterate on tests

## Static (host-safe, zero-dep)

```sh
./tests/test.sh
```

Covers `bash -n` syntax, every library script sourced by `install.sh`/`post-install.sh` (fail: "not sourced"), source-only `install_*`/`config_*` functions, the standalone `BASH_SOURCE` guard on every `*config*.sh`, and shellcheck only if installed. Fail-closed: any failure exits 1.

## Isolated static (no host deps)

```sh
docker compose -f tests/compose.yml run --rm test
```

Image `ubuntu:26.04` + bash/shellcheck, repo mounted read-only.

## Full e2e (needs Multipass on host)

```sh
./tests/test.sh --vm          # fresh VM, non-interactive CHEZMOI_NAME/EMAIL, SKIP_UPGRADE=1
./tests/test.sh --vm --keep   # leave VM running for inspection
./tests/test.sh --vm --reuse  # reuse existing VM for fast iteration
```

`--keep`/`--reuse` are only valid with `--vm`.

## Iteration loop (fast re-runs)

- Seed once with the full install: `./tests/test.sh --vm --keep` (VM kept alive).
- Then iterate: `./tests/test.sh --vm --reuse` — idempotency guards skip already-installed packages (~seconds).
- `--reuse` without a `--keep` seeding run: the VM is deleted on exit and the next run rebuilds fresh.
- Reset a dirty VM to its clean base with `multipass restore ubuntu-config-test.base`.

## Test-VM upgrade

`post-install.sh` runs `apt upgrade` unless skipped (test VMs only — run the full upgrade on real machines):

```sh
SKIP_UPGRADE=1 bash setup/post-install.sh
```