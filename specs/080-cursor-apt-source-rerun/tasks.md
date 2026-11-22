# tasks.md - `080-cursor-apt-source-rerun`

| ID  | Done | Task | Depends on | Type      | Verification |
| --- | ---- | ---- | ---------- | --------- | ------------ |
| 1   | [x]  | Add `tests/setup/development/cursor-test.sh`: hermetic tests for a fresh source, a rerun after the package rewrote the source, repair from the two-conflicting-entries state, byte-for-byte idempotence, source-only `source`, and other apt sources untouched. | - | Automated | `bash tests/setup/development/cursor-test.sh` fails against the current tree — the red state before task 2. |
| 2   | [x]  | Rewrite `install_cursor_repository()` in `setup/development/cursor.sh` to install `/usr/share/keyrings/anysphere.gpg`, write the DEB822 `/etc/apt/sources.list.d/cursor.sources`, and remove the legacy `cursor.list` and `cursor.gpg`; leave all other functions, version guards and step order unchanged. | 1 | Automated | `bash tests/setup/development/cursor-test.sh` passes; `bash -n` and `shellcheck -e SC1091` clean on `setup/development/cursor.sh`. |
| 3   | [x]  | Run the static gate and the isolated static check. | 2 | Automated | `./tests/test.sh` passes; `docker compose -f tests/compose.yml run --rm test` passes. |
| 4   | [ ]  | Seed a VM and verify the rerun path where issue #80 appears. | 3 | Manual | `./tests/run-with-logging.sh e2e ./tests/test.sh --vm --keep` followed by `./tests/run-with-logging.sh e2e ./tests/test.sh --vm --reuse` both pass; the reuse run exercises the previously failing `apt update`. Use `--keep` to inspect a failed VM. |
| 5   | [x]  | File the follow-up issue for a shared apt-source helper covering every vendor repository. | - | Manual | Issue [#100](https://github.com/MatiasOlivera/ubuntu-config/issues/100) exists and links the duplicate-source class of bug from #80. |
