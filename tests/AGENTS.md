# Test suite

Tests cover this repository's Bash setup and release scripts. `tests/test.sh` automatically runs every `*-test.sh` file under `tests/`.

## Architecture

> [Architecture] Uses Facade

## Conventions

- Keep `*-test.sh` checks self-contained and deterministic. Stub external commands and network clients; do not depend on live package, release, or download servers. Unexpected external requests should fail.
- Put writable state such as `HOME`, `TMPDIR`, and install prefixes in per-test temporary directories. Tests must not run system-mutating setup scripts on the host.
- Assert observable behavior, including status, output, files, and external-command calls. Avoid coupling assertions to private helper names.
- `tests/docker/chezmoi-ignore-check.sh` is container-only: it is not auto-discovered by `test.sh`, needs the pinned `chezmoi` from `tests/Dockerfile`, and fails loud with a Docker hint when invoked without it.

## Commands

See the root `AGENTS.md` for trusted-checkout restrictions and Multipass verification.
