# tasks.md - `46-antigravity-cli-integrity`

| ID | Done | Task | Depends on | Type | Verification |
| --- | --- | --- | --- | --- | --- |
| 1 | [x] | Align the #46 plan with the shared source-priority decision in ADR 0007 | - | Manual | `git diff --check`; review the plan against ADR 0007 and the live publisher manifests |
| 2 | [ ] | Replace remote installer execution with publisher-first verified artifact installation and GitHub digest fallback; add hermetic functional coverage | 1 | Automated | `tests/setup/development/antigravity-cli-test.sh`; then `./tests/test.sh`, Docker isolated checks, and the trusted-checkout VM install/rerun |
