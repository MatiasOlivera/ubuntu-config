# tasks.md - `192-explore-alternative-repository-names-description`

| ID  | Done | Task | Depends on | Type      | Verification |
| --- | ---- | ---- | ---------- | --------- | ------------ |
| 1   | [ ]  | Add a contract test that fails while active files still use the old repository name, excluding historical records and the deliberate legacy-state read. | - | Automated | `bash tests/repository-name-test.sh` fails before the rename and passes after task 4. |
| 2   | [ ]  | Add a failing case to the AnythingLLM test for a pre-rename version marker, then move the marker to an application-owned path and read the old marker once when the new one is absent. | 1 | Automated | `bash tests/setup/desktop-apps/anythingllm-test.sh` exits 0 with the legacy-marker case. |
| 3   | [ ]  | Rename runtime identifiers — container image, e2e VM prefix, state/cache/log paths, compose project and observability service name — to `ubuntu-workstation` in scripts, workflows, tests, dashboards and agent docs. | 2 | Automated | The focused tests for the touched scripts exit 0: `bash tests/vm-name-test.sh`, `bash tests/vm-cleanup-test.sh`, `bash tests/observability/wrapper-test.sh`, `bash tests/isolation-test.sh`. |
| 4   | [ ]  | Rename identity references in README, agent instructions, constitution, changelog generator config and issue-template links; set the proposed description and eight topics in the ADR-backed plan. | 3 | Automated | `bash tests/repository-name-test.sh` exits 0 and a manual read of `README.md` shows the new clone URL. |
| 5   | [ ]  | Move ADR 0019 from `proposed` to `accepted` once the plan is approved. | 4 | Manual | `docs/decisions/0019-repository-identity-naming.md` shows `Status: accepted`. |
| 6   | [ ]  | Apply the GitHub rename, description and topics in one mutation after explicit user approval. | 5 | Manual | `gh repo view --json name,description,repositoryTopics` shows the new values. |
| 7   | [ ]  | Publish the container image under the new package name and make that package public. | 6 | Manual | The `test-image` workflow run succeeds and an anonymous pull of the new image succeeds. |
| 8   | [ ]  | Update local clone/worktree remotes to the new repository URL. | 6 | Manual | `git remote -v` shows the new URL in this checkout. |
| 9   | [ ]  | Confirm an old repository URL still resolves to the renamed repository. | 6 | Manual | Opening the former URL lands on the renamed repository. |
| 10  | [ ]  | Run the full test gate before the first local review. | 4, 7 | Automated | `./tests/test.sh` exits 0. |
