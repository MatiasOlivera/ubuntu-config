---
name: run-tests
description: Use when running or iterating on this repo's checks while changing setup — scoped single-test/syntax checks during iteration, full ./tests/test.sh gate before review, docker-isolated compose check, Multipass e2e (--vm/--reuse/--keep), verifying an install change, choosing VM flags.
---

# Run and iterate on tests

## Observability for long runs

Every `./tests/test.sh --vm ...` phase already records its own transcript,
per-app spans and logs under `E2E_OBSERVABILITY_DIR` (default
`${XDG_DATA_HOME:-$HOME/.local/share}/ubuntu-config/observability/<run-id>/`).
The harness prints `records:` and `log:` paths; watch a live transcript with
`tail -f <log path>`. To browse traces, correlated logs and metrics, start the
local stack once (see `AGENTS.md`):

```sh
docker compose -f tests/observability/compose.yml up -d
# Grafana: http://localhost:3000 (admin/admin)
```

Live forwarding is best effort: an unreachable collector warns once and the
durable records remain complete. Never pipe a long run to `head` or `tail`:
`head` sends SIGPIPE mid-run (and `test.sh`'s EXIT trap can delete a kept VM),
while `tail` buffers until EOF and returns its own status, hiding a suite
failure. Do not pipe the runner itself either — use the printed `log:` path.

## Scoped iteration (default)

Iterate with the check that covers the change. The full gate below runs before the first local review, and again before the pull request only when review feedback changed code.

- Changed `setup/<area>/<name>.sh` → `bash tests/setup/<area>/<name>-test.sh`.
- Changed `reports/gaps.sh` → `bash tests/reports/gaps-test.sh`.
- Changed `tests/python/test_<name>.py` → `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/python -p 'test_<name>.py' -v`.
- Any changed `.sh` → `bash -n <path>` and `shellcheck -e SC1091 <path>` (skip shellcheck when not installed; `-e SC1091` matches `tests/test.sh`).

## Static (host-safe, zero-dep)

```sh
./tests/test.sh
```

Covers `bash -n` syntax, every library script sourced by `install.sh`/`post-install.sh` (fail: "not sourced"), source-only `install_*`/`config_*` functions, the standalone `BASH_SOURCE` guard on every `*config*.sh`, and shellcheck only if installed. Fail-closed: any failure exits 1. The source-only check executes library scripts, so run this on a trusted checkout; for untrusted changes use the Docker-isolated check below.

## Isolated static (no host deps)

```sh
docker compose -f tests/compose.yml run --rm test
```

Image `ubuntu:26.04` + shellcheck/python3, repo mounted read-only. This local
command always builds from `tests/Dockerfile`. CI pulls a prebuilt image from
GHCR instead; only PRs that change the image definition build locally. A nightly
cache-free rebuild validates apt and upstream packages, so keep that workflow
green when changing the toolchain.

## Full e2e (needs Multipass on host)

```sh
./tests/test.sh --vm          # fresh VM, non-interactive CHEZMOI_NAME/EMAIL, SKIP_UPGRADE=1
./tests/test.sh --vm --keep   # leave VM running for inspection
./tests/test.sh --vm --reuse  # reuse existing VM for fast iteration
```

`--keep`/`--reuse` are only valid with `--vm`.

The VM name is `ubuntu-config-test-<checkout-dir>-<base62>` (checkout directory slug + base62 digest of its path), so each checkout has its own VM; each `--vm` run prints the name.

## Iteration loop (fast re-runs)

- Seed once with the full install: `./tests/test.sh --vm --keep` (VM kept alive).
- Then iterate: `./tests/test.sh --vm --reuse` — idempotency guards skip already-installed packages (~seconds).
- `--reuse` without a `--keep` seeding run: the VM is deleted on exit and the next run rebuilds fresh.
- Reset a dirty VM to its clean base with `multipass restore <vm-name>.base` (`<vm-name>` is the worktree-scoped name printed by each `--vm` run).

## Test-VM upgrade

`post-install.sh` runs `apt upgrade` unless skipped (test VMs only — run the full upgrade on real machines):

```sh
SKIP_UPGRADE=1 bash setup/post-install.sh
```