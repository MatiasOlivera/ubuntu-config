# tasks.md - `48-install-opencode-from-verified-artifact`

| ID | Done | Task | Depends on | Type | Verification |
| --- | --- | --- | --- | --- | --- |
| T1 | [x] | Add hermetic V2 installer behavior tests with stubbed formula/archive downloads and temporary `HOME`; cover x64-baseline and arm64 selection, source-only Homebrew checksum use, skip-without-network, malformed/missing metadata, tampering, failed downloads, invalid archives, and unsupported architecture. | — | Automated | `tests/setup/development/opencode-test.sh` |
| T2 | [x] | Replace the V1 remote installer execution with V2 formula parsing, fail-closed SHA-256 verification, staged extraction, and installation under `$HOME/.opencode/bin`, preserving the existing version and dispatcher contracts. | T1 | Automated | `tests/setup/development/opencode-test.sh` |
| T3 | [x] | Review the completed change against every acceptance scenario and the source-only/dispatcher contracts. | T2 | Manual | Review `spec.md`, `setup/development/opencode.sh`, and `tests/setup/development/opencode-test.sh` against the scenarios and existing script contract. |
| T4 | [ ] | Run the trusted-checkout verification chain for the install-path change. | T3 | Automated | `./tests/test.sh`, then `docker compose -f tests/compose.yml run --rm test`, then `./tests/test.sh --vm --reuse`; stop at first failure. |
