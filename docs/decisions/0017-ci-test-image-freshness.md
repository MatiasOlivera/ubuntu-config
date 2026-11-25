# CI gate test image freshness

- Status: accepted
- Deciders: Matias Olivera
- Date: 2026-11-25

## Context and Problem Statement

The isolated gate chooses whether to run the suite in a published test image or
in one built from the checkout. The choice depends on the triggering event and
on a narrow comparison with a base ref, so the same commit can pass on a pull
request and fail on a push. A change that needs a new test tool can be checked
against an image that does not contain it. This record supersedes
`0010-ci-test-image-provisioning` on the point that pull requests validate
against the published image; that record's scheduled cache-free freshness check
remains authoritative.

## Decision Drivers

- A gate result must depend on the checkout under test, not on registry state or
  the triggering event.
- A new test dependency declared in the checkout must be available without a
  separate publication step.
- Push and pull-request runs of one commit must choose the same image source and
  produce the same result.
- Warm runs must stay fast and independent of mirror throughput.
- Broken apt repositories and changed upstream packages must still be detected
  by an independent check, not masked by reuse.
- The gate must keep running the full static suite in a clean, isolated Ubuntu
  environment.

## Considered Options

| Option | Outcome | Cost |
| --- | --- | --- |
| Build from the checkout on every run, reusing the published image only as a build cache | Won: checkout is authoritative; push and PR behave identically; no publication step on the critical path | Cold cache misses still reach mirrors, but only when the toolchain actually changes |
| Publish a content-addressed image and run only a matching tag | Lost: publication must finish ahead of the gate and a dependency declared outside the hashed inputs can still be missed | Extra publication and addressing surface |
| Build from the checkout with no cache reuse | Lost: reintroduces the mirror-bound cold runs that #111 measured at up to nearly the full job timeout | No extra setup, high recurring runtime |
| Publish an image for every commit or pull request before the gate runs | Lost: adds a release-like step to ordinary changes and cannot serve fork pull requests without publication rights | Per-trigger publication surface |
| Keep trusting the published image without a freshness rule | Lost: this is the stale-image failure the issue reports | Lowest, incorrect |

## Decision Outcome

Chosen option: **build from the checkout on every run, reusing the published
image only as a build cache**, because it is the only option where the checked
environment is always the one declared by the checkout and where trigger type
cannot change the result.

- Correctness never depends on what has been published or on when publication
  happened.
- The published image remains available and is refreshed, but its role is to
  speed up builds; it is never an authority for what the suite runs in.
- A scheduled cache-free rebuild and suite run remain the independent signal for
  repository and upstream health, as decided in `0010-ci-test-image-provisioning`.

### Positive Consequences

- Push and pull-request runs of the same commit are equivalent by construction.
- A new test dependency becomes available as soon as it is declared.
- Contributors no longer need to interpret a red check as either a code failure
  or a stale image.
- Warm runs keep apt mirrors off the critical path.

### Negative Consequences

- Runs that change the toolchain pay a cold build against upstream mirrors; the
  scheduled freshness check absorbs the recurring cost of detecting upstream
  drift.
- The published image and its registry remain part of the infrastructure, even
  though they are no longer on the correctness path.
- An unreachable cache degrades to a cold build rather than to a stale image;
  correctness is preserved at the cost of runtime.
