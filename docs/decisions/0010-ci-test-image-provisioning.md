# Docker-isolated CI image provisioning

- Status: accepted
- Deciders: Matias Olivera
- Date: 2026-11-23

## Context and Problem Statement

The Docker-isolated gate rebuilds its Ubuntu test image on every pull request. On a fresh runner the rebuild re-downloads apt metadata and packages from Ubuntu mirrors, whose throughput varies by an order of magnitude: identical runs took 59s to 593s against roughly 18s of actual checks, nearly exhausting the job timeout. The gate must become fast and predictable without weakening what it guarantees.

## Decision Drivers

- Cold runs must finish well within the timeout with margin independent of mirror throughput.
- Repeat runs must not re-download the same apt metadata and packages.
- The full static suite must still run in a clean Ubuntu environment.
- Broken apt repositories and changed upstream packages must be detected, not masked by reuse.
- Changes to the image definition must never be validated against a stale image.

## Considered Options

| Option                                     | Outcome                                                                                    | Cost                                     |
| ------------------------------------------ | ------------------------------------------------------------------------------------------ | ---------------------------------------- |
| Rebuild from scratch on every run           | Lost: mirror-bound and nearly times out                                                     | None                                     |
| Drop the isolated gate from pull requests   | Lost: removes the only clean-environment check                                              | None                                     |
| Runner-local artifact cache for image or apt data | Lost: cold runs and fork PRs still hit mirrors; cached apt data can mask broken repositories | Low, fails cold-run and detection drivers |
| Multi-stage image build                     | Lost: no compiled artifacts to copy, same packages downloaded, more fragile                 | Moderate                                 |
| Published image without a freshness check   | Lost: upstream drift and broken repositories would be masked by reuse                       | Lowest                                   |
| **Published image plus scheduled cold rebuild** | Won: removes mirrors from the critical path while keeping drift detection                | Registry setup and a scheduled workflow  |

## Decision Outcome

Chosen option: **published image plus scheduled cold rebuild**, because it is the only option that takes network variability off the pull-request path while preserving an independent check that the toolchain still builds from current upstream packages.

- Pull requests validate against a maintained published image; the image definition is built locally when it changes so a stale image cannot hide a broken change.
- A scheduled, cache-free rebuild and suite run is the authority for repository and upstream health; its failure is a signal that must be acted on.
- Layer caching is acceptable for ordinary image publication but not for the freshness check.

### Positive Consequences

- Pull-request runtime is dominated by the suite, not by package downloads.
- Repeat runs reuse the same toolchain without repeated downloads.
- Upstream breakage is detected on a predictable cadence instead of being hidden.

### Negative Consequences

- Adds a registry dependency and a scheduled workflow to maintain.
- The published image must be reachable without credentials for fork pull requests.
- Freshness checks run on a schedule, so breakage can land between checks and is not attributed to the pull request that exposed it.
- A changed upstream toolchain can turn pull requests red until the repository adapts; that is the intended detection, not a regression.
