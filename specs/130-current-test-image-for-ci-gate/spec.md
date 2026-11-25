# spec.md - `130-current-test-image-for-ci-gate`

## Context

Issue #130: the `docker-isolated` gate sometimes runs the full suite against a
previously published test image instead of an environment built from the
checkout under test. The choice is made by comparing the current checkout with
`github.base_ref` and looking only at two files; on a branch push the base ref
is empty and on many changes the environment-affecting difference is not in
those files. The result is that one commit can pass on its pull-request run and
fail on its push run, and a contributor cannot tell whether their change broke
the suite or the gate used an old image. ADR 0010 introduced the published
image to keep apt mirrors off the pull-request critical path; that speed
benefit must survive without making the image an authority for correctness.

## User stories

- As a contributor, I want the isolated gate to run my suite in an environment
  built from my checkout, so a green check means my change actually works.
- As a contributor adding a test dependency, I want the dependency available to
  the gate without publishing an image first, so I do not have to perform a
  release-like step for an ordinary change.
- As a reviewer, I want a push and a pull request of the same commit to produce
  the same result, so a red check is attributable to the code.
- As a maintainer, I want warm runs to stay fast and upstream breakage to be
  detected on a schedule, so the gate remains usable and trustworthy.

## Acceptance criteria (BDD)

```gherkin
Scenario: pull-request run uses the checkout's toolchain
  Given a pull request declares a tool the isolated suite needs
  When the docker-isolated gate runs on that pull request
  Then the suite runs in an image built from that checkout
  And the declared tool is available to the suite

Scenario: push and pull request of one commit agree
  Given one commit is both pushed to a branch and proposed in a pull request
  When both CI runs execute the docker-isolated gate
  Then both runs build the image from the same checkout
  And neither run selects its image source from the triggering event
  And both runs produce the same suite result

Scenario: a new dependency needs no publication step
  Given a contributor has declared a new test dependency in the checkout
  When the gate runs before any image has been published for that dependency
  Then the dependency is present in the image that runs the suite

Scenario: warm runs stay off the mirror critical path
  Given a published image contains the same toolchain as the checkout
  When the gate builds the image for the run
  Then the build reuses the published image's cached layers
  And apt metadata and packages are not re-downloaded

Scenario: an unavailable cache never weakens the gate
  Given the published image cannot be reached
  When the gate runs
  Then it still builds from the checkout and runs the full suite
  And no stale image is used to execute the suite

Scenario: clean environment and full suite are preserved
  Given any CI trigger of the docker-isolated gate
  When the suite runs
  Then it runs the full static suite in an Ubuntu container
  And the container has no network, no added capabilities, and no new privileges
  And the checkout is mounted read-only

Scenario: upstream drift is still detected independently
  Given the scheduled image job
  When it runs without a build cache
  Then it rebuilds the toolchain from current upstream packages
  And it runs the full suite against that image
  And it refreshes the published image with an importable build cache
```

## Constraints

- [ ] The gate must never skip or weaken a check because a tool is missing.
- [ ] Correctness must not depend on a publication step or on registry state;
      the published image is a performance aid only.
- [ ] The nightly cache-free rebuild and suite remain the independent signal
      for broken apt repositories and changed upstream packages (ADR 0010).
- [ ] Tests stay hermetic: no network, credentials, or live registry in
      `tests/test.sh`; contract checks read configuration only.
- [ ] The public GHCR package stays pullable without credentials so fork pull
      requests can use it as a cache source.
- [ ] `./tests/test.sh` stays green.
- [ ] Out of scope: changing the release workflow, adding a second registry
      cache, or changing the contents of the static suite.

## Assumptions

- Compose `cache_from` with a registry reference imports cache from an image
  that was published with inline cache metadata. Source: Docker Compose build
  reference and cache backend docs, queried 2026-11-25. Verification: contract
  check asserts both sides; first CI run confirms warm-build timing. Provisional
  until observed.
- An unreachable or unsupported cache source does not prevent a Compose build.
  Source: Compose specification (`cache_from`) docs, queried 2026-11-25.
  Verification: local build with an unreachable ref during implementation;
  first CI run with the registry available.
- GitHub-hosted runners provide Compose v2 with BuildKit, which supports
  `cache_from`. Source: current runner images. Verification: first CI run.
  Provisional until observed.
