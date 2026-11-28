---
name: run-tests
description: Use when running or iterating on this repo's checks while changing setup — scoped single-test/syntax checks during iteration, full ./tests/test.sh gate before review, docker-isolated compose check, Multipass e2e (--vm/--reuse/--keep), verifying an install change, choosing VM flags.
---

# Run and iterate on tests

> [Architecture] Uses Facade

## Observability for long runs

Every `./tests/test.sh --vm ...` phase already records its own transcript,
per-app spans and logs under `E2E_OBSERVABILITY_DIR` (default
`${XDG_DATA_HOME:-$HOME/.local/share}/ubuntu-workstation/observability/<run-id>/`).
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

The local stack provisions an **E2E runs** dashboard and alert rules under
**E2E Observability**; alerts are for local definition and evaluation only, with
no notification channel. Span and record timing come from replayed Loki records,
so it is available even when the stack starts after a run; trace-metric panels
fill in only when it runs during the run. See
[decision 0012](../../../docs/decisions/0012-local-grafana-feature-scope.md) and the
[Grafana query cookbook](../../../docs/runbooks/grafana-query-cookbook.md) for
ready-made queries and the trace-to-logs walkthrough.

## Scoped iteration (default)

Iterate with the check that covers the change. The full gate below runs before the first local review, and again before the pull request only when review feedback changed code.

- Changed `setup/<area>/<name>.sh` → `bash tests/setup/<area>/<name>-test.sh`.
- Changed `reports/gaps.sh` → `bash tests/reports/gaps-test.sh`.
- Changed `tests/python/test_<name>.py` → `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/python -p 'test_<name>.py' -v`.
- Any changed `.sh` → `bash -n <path>` and `shellcheck -e SC1091 <path>` (skip shellcheck when not installed; `-e SC1091` matches `tests/test.sh`).
- Changed `dotfiles/.chezmoiignore` → `bash tests/docker/chezmoi-ignore-check.sh`. This check is container-only and needs the `chezmoi` binary; without it, use the Docker command below.

## Static (zero-dep, no script execution)

```sh
./tests/test.sh
```

Covers `bash -n` syntax, every library script sourced by `install.sh`/`post-install.sh` (fail: "not sourced"), source-only `install_*`/`config_*` functions, the standalone `BASH_SOURCE` guard on every `*config*.sh`, and shellcheck only if installed. Fail-closed: any failure exits 1. The source-only check parses declarations rather than sourcing scripts, so it does not execute library code. The functional tests still run test scripts, so use a trusted checkout — or the Docker-isolated check below for untrusted changes.

Python metadata parser unit tests use only the standard library and local fixtures (no network):

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/python -v
```

## Isolated static (no host deps)

```sh
docker compose -f tests/compose.yml run --rm test
```

Image `ubuntu:26.04` + shellcheck/python3/git/curl and a pinned, checksummed
chezmoi; repo mounted read-only. The command runs the static suite plus the
container-only `tests/docker/chezmoi-ignore-check.sh`. This local command and
every CI trigger build from `tests/Dockerfile`; the published GHCR image is only
a build cache, never the image the suite runs in — an unreachable cache degrades
to a cold build, not a stale image. A nightly cache-free rebuild validates apt
and upstream packages and refreshes that cache, so keep that workflow green
when changing the toolchain ([ADR 0010](../../../docs/decisions/0010-ci-test-image-provisioning.md),
[ADR 0017](../../../docs/decisions/0017-ci-test-image-freshness.md)). One-time
setup: make the `ubuntu-workstation-test` GHCR package public so fork PRs can use the
cache without credentials.

## Full e2e (needs Multipass on host)

```sh
./tests/test.sh --vm          # fresh VM, non-interactive CHEZMOI_NAME/EMAIL, SKIP_UPGRADE=1
./tests/test.sh --vm --keep   # leave VM running for inspection
./tests/test.sh --vm --reuse  # reuse existing VM for fast iteration
```

`--keep`/`--reuse` are only valid with `--vm`.

MCP OAuth sign-in is interactive, so the headless e2e VM verifies that the
Context7 entries are deployed but does not authenticate them.

The VM name is `ubuntu-workstation-test-<checkout-dir>-<base62>` (checkout directory slug + base62 digest of its path), so each checkout has its own VM; each `--vm` run prints the name. Only one e2e run may use a given VM at a time: starting a second `--vm` run against the same checkout exits immediately with an error naming the VM. It does not queue, and runs against other worktrees are unaffected. Wait for the active run to finish before retrying.

Deleting an Orca worktree with hooks enabled (`orca worktree rm --worktree <selector> --run-hooks`) runs the `scripts.archive` hook from `orca.yaml`, which purges only that checkout's VM. A failed purge never blocks deletion: it notifies on the desktop and appends the VM name to `${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-workstation/vm-cleanup-failures.log`.

## Iteration loop (fast re-runs)

- Seed once with the full install: `./tests/test.sh --vm --keep` (VM kept alive).
- Then iterate: `./tests/test.sh --vm --reuse` — idempotency guards skip already-installed packages (~seconds). This is the check to run before a pull request.
- For a single-app edit, use `bash tests/dev-iter.sh seed` once after seeding the VM, then `bash tests/dev-iter.sh` to run `apt update` and only the changed setup scripts. It is a development shortcut, not verification; the stored baseline advances after each successful run.
- `--reuse` without a `--keep` seeding run: the VM is deleted on exit and the next run rebuilds fresh.
- Reset a dirty VM to its clean base with `multipass restore <vm-name>.base` (`<vm-name>` is the worktree-scoped name printed by each `--vm` run).

## Test-VM upgrade

`post-install.sh` runs `apt upgrade` unless skipped (test VMs only — run the full upgrade on real machines):

```sh
SKIP_UPGRADE=1 bash setup/post-install.sh
```
