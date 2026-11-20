# tasks.md - `46-antigravity-cli-integrity`

| ID | Done | Task | Depends on | Type | Verification |
| --- | --- | --- | --- | --- | --- |
| 1 | [x] | Record the Antigravity integrity source decision and technical plan | - | Manual | `git diff --check`; review decision against live publisher manifests and ADR 0003 |
| 2 | [ ] | Replace remote installer execution with publisher-first verified artifact installation and GitHub digest fallback; add hermetic functional coverage | 1 | Automated | `tests/setup/development/antigravity-cli-test.sh`; then `./tests/test.sh`, Docker isolated checks, and the trusted-checkout VM install/rerun |
