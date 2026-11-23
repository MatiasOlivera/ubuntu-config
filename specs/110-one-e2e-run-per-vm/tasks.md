# tasks.md - `110-one-e2e-run-per-vm`

| ID  | Done | Task | Depends on | Type | Verification |
| --- | ---- | ---- | ---------- | ---- | ------------ |
| 1   | [x]  | Record the concurrency decision as `docs/decisions/0010-e2e-run-concurrency.md` | - | Manual | File exists with every MADR section filled and option-neutral title; reviewed against the template |
| 2   | [x]  | Write the failing hermetic contention test `tests/vm-lock-test.sh` (red) | - | Automated | `bash tests/vm-lock-test.sh` exits 1 while the helper is absent; no Multipass, sudo, apt, network or downloads called |
| 3   | [ ]  | Implement `tests/vm-lock.sh` acquire/release and make the test pass (green), then simplify if needed | 2 | Automated | `bash tests/vm-lock-test.sh` passes; `bash -n tests/vm-lock.sh`; `shellcheck -e SC1091 tests/vm-lock.sh` |
| 4   | [ ]  | Wire the guard into `tests/test.sh` before Phase 1; remove the later duplicate VM-name computation | 3 | Automated | `bash -n tests/test.sh`; `shellcheck -e SC1091 tests/test.sh`; `./tests/test.sh` static gate stays green |
| 5   | [ ]  | Document the guard in `README.md` (Testing) and `.agents/skills/run-tests/SKILL.md` (VM naming / iteration loop) | 4 | Manual | Both sections state fail-fast per-VM behavior; grep and read-back, no stale wording |
| 6   | [ ]  | Run the full static gate, including every `*-test.sh` under `tests/` | 3, 4, 5 | Automated | `./tests/test.sh` exits 0 with all checks passing, including the new guard test |
| 7   | [ ]  | Verify contention on a real Multipass host: start `./tests/test.sh --vm --keep`, start a second run while it is active, then confirm a run works after the first exits | 6 | Manual | Second run exits immediately with an error naming the VM and makes no VM change; subsequent run starts normally; console transcript kept |
