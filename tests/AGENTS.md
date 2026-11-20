# Test suite

Tests cover this repository's Bash setup scripts. `tests/test.sh` automatically runs every `*-test.sh` file under `tests/`.

## Conventions

- Keep `*-test.sh` checks self-contained and deterministic. Stub external commands and network clients; do not depend on live package, release, or download servers. Unexpected external requests should fail.
- Put writable state such as `HOME`, `TMPDIR`, and install prefixes in per-test temporary directories. Tests must not run system-mutating setup scripts on the host.
- Assert observable behavior, including status, output, files, and external-command calls. Avoid coupling assertions to private helper names.

## Commands

- Run one test: `bash tests/path/to/name-test.sh`.
- Run the full suite: `./tests/test.sh`.
- Run in Docker: `docker compose -f tests/compose.yml run --rm test`.
- Lint test scripts when ShellCheck is available: `find tests -name '*-test.sh' -print0 | xargs -0 shellcheck`.

See the root `AGENTS.md` for trusted-checkout restrictions and Multipass verification.
