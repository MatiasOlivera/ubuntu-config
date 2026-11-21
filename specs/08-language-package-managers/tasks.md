# tasks.md - `08-language-package-managers`

| ID  | Done | Task | Depends on | Type      | Verification |
| --- | ---- | ---- | ---------- | --------- | ------------ |
| 1   | [x]  | Write `docs/language-package-managers.md` with the three defaults, fallbacks, rejected options, tie-breakers, deferred languages, and links to ADR 0003/0007. | - | Manual | Human reads the doc; all acceptance scenarios about policy content pass. |
| 2   | [x]  | Add `tests/setup/development/pnpm-test.sh` (red): skip guard, verified install from stubbed GitHub release, missing/invalid digest, bad URL, missing asset, checksum mismatch, unsupported arch. | - | Automated | `bash tests/setup/development/pnpm-test.sh` fails before task 3. |
| 3   | [x]  | Implement `setup/development/pnpm.sh` (`install_pnpm`, `pnpm_version`, release metadata helper, `~/.local/bin` target) so task 2 goes green. | 2 | Automated | `bash tests/setup/development/pnpm-test.sh` passes. |
| 4   | [x]  | Wire pnpm into `setup/install.sh` (source + step) and `reports/versions.sh` (`src` + `chk`); add README Development bullet. | 3 | Automated | `./tests/test.sh` contract passes; report shows a `pnpm` row. |
| 5   | [x]  | Add `tests/setup/development/bun-test.sh` (red): skip guard, publisher `SHASUMS256.txt` verification, missing/mismatched checksum, failed download, absent asset, unsupported arch, preserved `.bun` layout. | - | Automated | `bash tests/setup/development/bun-test.sh` fails before task 6. |
| 6   | [ ]  | Implement `setup/development/bun.sh` (`install_bun`, `bun_dependencies`, `bun_version`, publisher checksum verification, `$HOME/.bun` target) so task 5 goes green. | 5 | Automated | `bash tests/setup/development/bun-test.sh` passes. |
| 7   | [ ]  | Wire bun into `setup/install.sh` (source + step) and `reports/versions.sh` (`src` + `chk`); add README Development bullet. | 6 | Automated | `./tests/test.sh` contract passes; report shows a `bun` row. |
| 8   | [ ]  | Update `AGENTS.md` (Rules + Decisions) and the README policy pointer to the live document; keep bun dotfile lines untouched. | 1 | Manual | Grep shows both files reference `docs/language-package-managers.md`; no MADR added. |
| 9   | [ ]  | Run the full verify chain: static checks, isolated Docker checks, then `./tests/test.sh --vm --reuse` for the real release API and PATH behavior. | 4, 7, 8 | Manual | Each command exits 0; VM report lists pnpm and bun rows. |
