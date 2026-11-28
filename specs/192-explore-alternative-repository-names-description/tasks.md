# tasks.md - `192-explore-alternative-repository-names-description`

| ID  | Done | Task | Depends on | Type      | Verification |
| --- | ---- | ---- | ---------- | --------- | ------------ |
| 1   | [x]  | Move the AnythingLLM version marker to an application-owned path. | - | Automated | `bash tests/setup/desktop-apps/anythingllm-test.sh` exits 0. |
| 2   | [x]  | Rename runtime identifiers — container image, e2e VM prefix, state/cache/log paths, compose project and observability service name — to `ubuntu-workstation` in scripts, workflows, tests, dashboards and agent docs. | 1 | Automated | The focused tests for the touched scripts exit 0: `bash tests/vm-name-test.sh`, `bash tests/vm-cleanup-test.sh`, `bash tests/observability/wrapper-test.sh`, `bash tests/isolation-test.sh`. |
| 3   | [x]  | Rename identity references in README, agent instructions, constitution, changelog generator config and issue-template links. | 2 | Manual | A grep for the former name in active files finds only historical records; `README.md` shows the new clone URL. |
| 4   | [ ]  | Move ADR 0019 from `proposed` to `accepted` once the plan is approved. | 3 | Manual | `docs/decisions/0019-repository-identity-naming.md` shows `Status: accepted`. |
| 5   | [ ]  | Apply the GitHub rename, description and topics after explicit user approval. | 4 | Manual | `gh repo view --json name,description,repositoryTopics` shows the new values. |
| 6   | [ ]  | Publish the container image under the new package name and make that package public. | 5 | Manual | The `test-image` workflow run succeeds and an anonymous pull of the new image succeeds. |
| 7   | [ ]  | Update local clone/worktree remotes to the new repository URL. | 5 | Manual | `git remote -v` shows the new URL in this checkout. |
| 8   | [ ]  | Confirm an old repository URL still resolves to the renamed repository. | 5 | Manual | Opening the former URL lands on the renamed repository. |
| 9   | [ ]  | Run the full test gate before the first local review. | 3, 6 | Automated | `./tests/test.sh` exits 0. |
