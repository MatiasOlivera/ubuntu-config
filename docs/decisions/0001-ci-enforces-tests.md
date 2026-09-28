# CI enforces tests

- Status: accepted
- Deciders: Matias Olivera
- Date: 2026-09-28

## Context and Problem Statement

PRs were landing with no automated check. We need CI that stays on the GitHub free tier while deciding what runs there: the fast static test, the Docker-isolated test, the Multipass e2e, or nothing at all.

## Decision Drivers

- Public repository: standard GitHub-hosted runners are free with unlimited minutes; larger runners bill even on public repos.
- Private-repo quota (Free plan: 2000 min/month) must never be touched by design.
- Standard runners have no supported nested virtualization for Multipass.
- `install.sh` performs ~30 external installs (Chrome, Docker, Ollama, Homebrew, …) taking 30–60+ min and flaking on network/apt drift.
- Contributors need a ~2 min deterministic signal on every PR.

## Considered Options

| Option                                      | Outcome                                                                             | Cost                     |
| ------------------------------------------- | ----------------------------------------------------------------------------------- | ------------------------ |
| Manual tests only (local, no CI)            | Lost: no enforcement on PRs, regressions land silently                              | Zero setup, zero signal  |
| **Fast-only CI (static + Docker-isolated)** | Won: free, fast, deterministic PR gate                                              | ~2 min per run, one file |
| Fast CI + manual e2e via workflow_dispatch  | Lost: Multipass has no nested virt on standard runners, slow and flaky              | 30–60+ min, flake triage |
| Full install.sh on the runner               | Lost: pollutes runner, Docker-in-Docker/snap/systemd gaps, longest and flakiest     | 30–60+ min, high triage  |
| Self-hosted runner for e2e                  | Lost: we pay the machine and its maintenance for a test that stays valuable locally | Ongoing infra cost       |

## Decision Outcome

Chosen option: **fast-only CI**, because it is the only option that is free, deterministic, and fast enough to gate every PR.

- CI runs `./tests/test.sh` (static) and `docker compose -f tests/compose.yml run --rm test` (isolated) on `ubuntu-26.04`, pinned to match `UBUNTU_IMAGE`.
- Workflow lives at `.github/workflows/test.yml`, triggers `push`, `pull_request`, `workflow_dispatch`; no `schedule`.
- Multipass e2e stays local: `./tests/test.sh --vm`, iterate with `--vm --reuse`, inspect with `--vm --keep`.

### Positive Consequences

- Every PR gets a free ~2 min gate; shellcheck always enforced via the Docker job.
- Pinned `ubuntu-26.04` runner matches the tested release, immune to `ubuntu-latest` migration drift.

### Negative Consequences

- CI will not catch install-time breakage (broken apt repos, upstream renames); mitigation is a local `--vm` run before releases, plus the `versions.sh` report.
