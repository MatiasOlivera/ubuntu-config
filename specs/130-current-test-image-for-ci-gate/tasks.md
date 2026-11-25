# tasks.md - `130-current-test-image-for-ci-gate`

| ID  | Done | Task | Depends on | Type      | Verification |
| --- | ---- | ---- | ---------- | --------- | ------------ |
| 1   | [x]  | Record ADR 0017, superseding 0010 in part | -          | Manual    | `docs/decisions/0017-ci-test-image-freshness.md` read; 0010 untouched |
| 2   | [x]  | Red: add gate contract checks to `tests/isolation-test.sh` (no mode selection or pull, build step present) and scope the `docker run` flag loop to the publishing workflow | 1          | Automated | `bash tests/isolation-test.sh` fails against current config; `bash -n tests/isolation-test.sh` |
| 3   | [x]  | Green: reduce `.github/workflows/test.yml` to one build-and-run step for every trigger; remove `TEST_IMAGE`, mode selection and image pull | 2          | Automated | `bash tests/isolation-test.sh` and `./tests/test.sh` green |
| 4   | [x]  | Red then green: add cache/freshness contract checks, then declare the published image as a Compose registry cache source and export inline cache metadata from both publish paths in `.github/workflows/test-image.yml` | 2          | Automated | `bash tests/isolation-test.sh`, `./tests/test.sh`, `docker compose -f tests/compose.yml config` green |
| 5   | [x]  | Delete `tests/ci-image-mode.sh` and `tests/ci-image-mode-test.sh` | 3          | Automated | `./tests/test.sh` green; repository grep finds no references |
| 6   | [ ]  | Update `README.md` (Testing and Ubuntu-version sections) and `.agents/skills/run-tests/SKILL.md` so docs describe build-always and cache-only | 4          | Manual    | Read both files; grep finds no image-mode or pull-in-CI description |
| 7   | [ ]  | Run the full gate and first isolated CI check | 3, 4, 5, 6 | Manual    | `./tests/test.sh`, `docker compose -f tests/compose.yml run --rm test`, and `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/python -v` all green; first CI isolated job builds from checkout |
