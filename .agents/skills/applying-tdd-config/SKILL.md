---
name: applying-tdd-config
description: Use when applying the hub TDD skill (mo-applying-tdd) to a change in this repo — maps red/green/refactor to the tests/test.sh contract suite and delegates command choice to run-tests.
---

# Apply TDD in this repo

Hub methodology lives in `mo-applying-tdd`. This skill only maps it to this
repo's checks: no methodology is copied and no runner command is hard-coded.

## When to use

- Implementing a behavior change in `setup/` or `dotfiles/`.
- Adding or extending a contract check, or reviewing whether a change followed the tests-first loop.

## Instructions

1. Red: write or extend the failing contract check — `tests/test.sh`, or the scoped `tests/setup/<area>/<name>-test.sh` for a single script — before or with the script change. Confirm it fails because the contract is absent, not because of syntax, a missing import, or a broken harness. A check that cannot run is not red.
2. Green: make the smallest script or config change that passes the check. Never weaken, delete, or skip the check to get there.
3. Refactor only while green; rerun the same check after each change and keep it passing.
4. Treat the contract suite as the behavior (outer) loop and one scoped check as the inner loop; prefer the lowest-level check that proves the behavior.
5. Resolve every "run the tests" step through the `run-tests` skill, including the full gate before the first local review.
