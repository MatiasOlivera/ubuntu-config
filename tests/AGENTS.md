# Test suite

This repository's tests exercise the Bash setup scripts without changing the host system.

## Test rules

- Keep functional tests hermetic and deterministic. Stub download and API clients (`curl`, `wget`, or similar) and serve fixture data locally; never call a real download or release server from a test. Unexpected network requests must fail.
- Use temporary directories for `HOME`, `TMPDIR`, install prefixes, and other writable state. Do not invoke system-mutating setup scripts on the host.
- Assert observable behavior such as exit status, output, created files, and recorded stub calls. Avoid depending on internal helper names.
- Build small archive fixtures and their genuine checksums during the test when integrity behavior is under test.

## Run and lint tests

- Run one functional test: `bash tests/setup/development/fnm-test.sh` (replace the path with the target test).
- Run all repository checks: `./tests/test.sh`.
- Run the isolated static suite: `docker compose -f tests/compose.yml run --rm test`.
- Lint test scripts when ShellCheck is available: `find tests -name '*-test.sh' -print0 | xargs -0 shellcheck`.

See the root `AGENTS.md` for trusted-checkout restrictions and the Multipass end-to-end test command.
