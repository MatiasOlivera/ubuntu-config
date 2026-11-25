# plan.md - `130-current-test-image-for-ci-gate`

## Architecture

The isolated gate stops choosing an image source. Every trigger builds the test
image from the checkout and runs the full static suite in it. A published image
remains in GHCR, but only as a cache source for that build; the nightly
cache-free job keeps detecting upstream drift and refreshes the published image
with cache metadata that a later build can import.

Components touched:

1. `.github/workflows/test.yml:27-56` — remove the `TEST_IMAGE` env, the mode
   step and the published-image step. Keep one `docker compose -f
   tests/compose.yml run --rm test` step for all triggers. `static` and
   `concurrency` are unchanged.
2. `tests/compose.yml:2-8` — declare the published image as a registry build
   cache while keeping `pull_policy: build`, so the image is still built from
   this checkout on every run.
3. `.github/workflows/test-image.yml:33-54` — both publish paths export inline
   cache metadata into the pushed image; the scheduled path stays cache-free on
   import. Triggers and the validation run are unchanged.
4. `tests/ci-image-mode.sh` and `tests/ci-image-mode-test.sh` — delete. No other
   file references them (verified by repository grep, 2026-11-25). `tests/test.sh:156-164`
   discovers test files by glob, so removing the test file needs no edit there.
5. `tests/isolation-test.sh:20-31` — the workflow loop currently asserts the
   `docker run` hardening flags in both workflows; `test.yml` no longer contains
   `docker run`, so scope that loop to `test-image.yml`. Add contract checks:
   `test.yml` has no mode selection, image pull, or `TEST_IMAGE`; it runs the
   Compose build; `compose.yml` declares the registry cache; `test-image.yml`
   exports inline cache. Satisfies scenarios 2, 3, 5 and 6.
6. `README.md:159-163,199-208` — describe the build-always gate, the cache-only
   role of the published image, and the unchanged nightly drift check; rename
   the Compose version pin to a cache-image reference.
7. `docs/decisions/0017-ci-test-image-freshness.md` (new) and
   `docs/decisions/0010-ci-test-image-provisioning.md` (unchanged, superseded in
   part). Satisfies the decision-driver constraint that reuse stays a
   performance aid only.

Implementation order: decision record and spec artifacts → workflow and Compose
changes → removal of the mode scripts → contract checks → docs → full gate.

## Data models

None. No schema or persisted format changes; the published image is a cache
artifact whose role changes from authority to acceleration (ADR 0017).

## API contracts

- Gate contract: any trigger of `.github/workflows/test.yml` executes exactly one
  isolated step that builds from the checkout and runs `./tests/test.sh`; no
  trigger-dependent image selection. Satisfies scenarios 1, 2 and 3.
- Cache contract: the published image carries inline cache metadata; Compose
  declares that image as a registry cache source and still builds every run.
  An unavailable cache degrades to a cold build, not to a stale image. Satisfies
  scenarios 4 and 5.
- Isolation contract: the built image runs the full static suite with no
  network, all capabilities dropped, no new privileges, and a read-only mount.
  Satisfies scenario 6.
- Freshness contract: the scheduled job performs a cache-free rebuild, runs the
  full suite and publishes a refreshed cache-bearing image. Satisfies
  scenario 7.
- Test contract: `tests/isolation-test.sh` asserts the above statically without
  network or Docker; `tests/test.sh:156-164` runs it as part of the full suite.
  Satisfies the constraint that tests stay hermetic.

## Decisions

- `docs/decisions/0017-ci-test-image-freshness.md` — build from the checkout on
  every run; published image is a cache only; scheduled cache-free rebuild
  remains the upstream-health authority. Supersedes part of
  `0010-ci-test-image-provisioning`.

## Risks

- **Cold cache miss.** A toolchain change makes the cache unusable and the build
  reaches Ubuntu mirrors. Mitigation: this is the intended trade-off in ADR
  0017 and only happens when the image definition changes; the nightly job
  exercises the same path on a schedule.
- **Registry unavailable or private.** Fork pull requests cannot authenticate to
  GHCR. Mitigation: the package stays public; an unusable cache is ignored and
  the build proceeds from the checkout.
- **Inline cache import not effective.** A published image without importable
  metadata silently restores cold builds. Mitigation: both publish paths export
  inline cache; contract check asserts it; first CI run confirms timing.
- **Contract checks drift.** Grep-based assertions can pass on a differently
  spelled but broken workflow. Mitigation: checks assert the exact build command
  and the absence of the old mode selector, and the full gate still runs.
- **Stale documentation.** README still describes image-mode selection.
  Mitigation: same change updates the Testing and Ubuntu-version sections.

## Assumptions

- Compose `cache_from` with a registry reference imports cache from an image
  published with inline cache metadata. Source: Docker Compose build reference
  and cache backend docs queried 2026-11-25 (spec.md assumptions). Verification:
  contract check on both sides plus warm-build timing on the first CI run.
- An unreachable or unsupported cache source does not prevent a Compose build.
  Source: Compose specification docs queried 2026-11-25. Verification: local
  build with an unreachable reference during implementation.
- GitHub-hosted runners provide Compose v2 with BuildKit. Source: current runner
  images. Verification: first CI run of the isolated job.
- The static suite needs only the tools already declared in `tests/Dockerfile`
  (`tests/Dockerfile:1-6`). Verification: `./tests/test.sh` in the built image on
  every gate run.
