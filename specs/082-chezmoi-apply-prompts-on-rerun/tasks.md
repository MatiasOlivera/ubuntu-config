# tasks.md - `082-chezmoi-apply-prompts-on-rerun`

| ID  | Done | Task | Depends on | Type      | Verification |
| --- | ---- | ---- | ---------- | --------- | ------------ |
| 1   | [x]  | Add `tests/setup/dotfiles-convergence-test.sh`: stub `curl` with a fake oh-my-zsh installer that records its arguments; assert `--keep-zshrc` and `--unattended` are passed, assert the installed guard skips the installer, and assert `install.sh` applies dotfiles with `--force`. Confirm it fails on the unmodified tree. | - | Automated | `bash tests/setup/dotfiles-convergence-test.sh` exits nonzero with all three assertions reported |
| 2   | [x]  | Pass `--keep-zshrc --unattended` (with the empty `$0` placeholder) to the oh-my-zsh installer in `install_oh_my_zsh`. | 1 | Automated | The installer-arguments and installed-guard assertions in `tests/setup/dotfiles-convergence-test.sh` pass |
| 3   | [x]  | Add `--force` to the `step chezmoi` apply command in `setup/install.sh`. | 1 | Automated | The apply-step assertion in `tests/setup/dotfiles-convergence-test.sh` passes |
| 4   | [x]  | Focused checks on the two changed setup scripts. | 2, 3 | Automated | `bash -n` and shellcheck clean on both scripts; focused test exits 0 |
| 5   | [x]  | Run the full repository gate. | 4 | Automated | `./tests/test.sh` exits 0 |
| 6   | [x]  | Run the isolated static check. | 5 | Automated | `docker compose -f tests/compose.yml run --rm test` exits 0 |
| 7   | [ ]  | Verify a rerun on an already-configured VM (the #30 regression path). | 6 | Manual | `./tests/test.sh --vm --reuse` (use `--keep` on failure): no TTY error, versions report printed, exit 0 |
| 8   | [ ]  | Self-review the change against the five acceptance scenarios. | 7 | Manual | Each scenario in `specs/082-chezmoi-apply-prompts-on-rerun/spec.md` is checked off against observed behavior |
