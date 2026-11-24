# Repeat verification overhead

- Status: accepted
- Deciders: Matias Olivera
- Date: 2026-11-24

## Context and Problem Statement

The measurement phase of #78 produced reliable per-run totals and a ranked
slow-step view. A warm verification run took about 105 seconds while the two
setup scripts reported 20 and 2 seconds of work. Early estimates attributed the
gap to the number of remote command sessions, but direct measurement disproved
that: a bare remote call takes about 0.2 seconds and a full phase wrapper,
including record copying, about 2 seconds. The real cause is stream ownership —
both setup commands start a background helper whose output stream is inherited,
so when the command finishes, an orphaned sleep keeps the caller's pipe open and
the remote call waits for end of file. A controlled reproduction with a 15-second
orphaned sleep took 15.2 seconds; redirecting the helper's streams inside a test
VM reduced the gap from 31–50 seconds to about 0.4 seconds.

The same investigation measured data movement and resource sizing to decide
whether other changes were worthwhile: shipping the checkout and collecting
records took under a second by either a file transfer or a classic mount, a
native mount required stopping the VM, and one larger-allocation install was
about 8 percent faster than the baseline. The choice is what to change, with the
measurements now contradicting the original hypothesis.

## Decision Drivers

- The repeat loop is the run developers perform most often.
- Fix the measured root cause rather than the most visible peripheral cost.
- Cold runs must remain trustworthy proof of a fresh install.
- Broken repositories and upstream changes must still be detected.
- The change should be small, reversible and verifiable without a live VM.
- Extra infrastructure or unproven tuning must not be adopted on assumption.

## Considered Options

| Option | Outcome | Cost |
| --- | --- | --- |
| Make background helpers release the caller's output streams | Won: removes the measured 31–50 s delay with a two-line change | Small |
| Batch remote command sessions into fewer calls | Lost: each call costs ~0.2 s, so the saving is ~1–2 s, not 80 s | Moderate |
| Cache downloaded apt packages across runs | Lost: transfers run at tens of megabytes per second; long steps are installation work | Moderate |
| Expose the checkout through a persistent shared folder | Lost: data movement is under a second and native mounts need a stopped VM | Moderate |
| Increase CPU or memory on the verification machine | Deferred: a single sample showed ~8 %, not enough evidence to change defaults | Small |
| Run package installation steps in parallel | Lost: the package manager serializes installs behind a lock | Moderate |

## Decision Outcome

Chosen option: **make the background helpers in both setup commands release
their inherited output streams**, because the measurements identify stream
ownership, not remote call count, as the dominant cost on every repeat run.

- Cold runs, repository validation and integrity-checked downloads stay exactly
  as they are, so fresh-clone reproducibility and upstream freshness detection
  are preserved.
- Phase reporting, failure attribution and record collection are untouched; a
  faster run is not a less informative one.
- The speedup is accepted with before and after wall-clock numbers for the same
  warm-VM scenario and a hermetic check on the stream behaviour.
- No mount, cache or resource-default change is adopted from a single sample.

### Positive Consequences

- The repeat loop recovers most of its wasted 31–50 seconds.
- No new cache, mount, service or persisted state to maintain or invalidate.
- The change is local, tiny and easy to revert.

### Negative Consequences

- The background helper's sleep still runs briefly after the command exits; it
  no longer holds the caller's pipe open, but the process is not reaped early.
- The gain applies mostly to repeat runs; cold installs keep their full duration.
- If a future setup step adds another inherited background stream, the delay
  would return; the regression test guards against that.
