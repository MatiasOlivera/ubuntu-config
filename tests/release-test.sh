#!/usr/bin/env bash
# Hermetic release-contract checks. Real git in throwaway clones; gh and the
# pinned tool are stubbed, so no network, credentials or real release is used.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_SH="$ROOT/scripts/release.sh"
TOOL_SH="$ROOT/scripts/git-cliff.sh"
WORKFLOW="$ROOT/.github/workflows/release.yml"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/release-test.XXXXXX")"
if [ -n "${RELEASE_TEST_KEEP:-}" ]; then
	printf 'sandbox: %s\n' "$TMP_ROOT"
else
	trap 'rm -rf "$TMP_ROOT"' EXIT
fi

CASES=0
FAILED=0
SKIPPED=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILED=$((FAILED + 1))
}

ok() {
	printf 'ok: %s\n' "$1"
}

state_get() {
	grep "^$1=" "$S/state" 2>/dev/null | cut -d= -f2- | head -n 1 || true
}

state_set() {
	local key=$1 value=$2
	grep -v "^$key=" "$S/state" >"$S/state.next" 2>/dev/null || true
	printf '%s=%s\n' "$key" "$value" >>"$S/state.next"
	mv "$S/state.next" "$S/state"
}

# Fresh bare origin + local clone with v0.3.0 and two unreleased commits.
setup() {
	CASES=$((CASES + 1))
	S="$TMP_ROOT/case$CASES"
	mkdir -p "$S/bin" "$S/local/.github"
	printf 'CI=success\nCI_SHA=develop\nVERSION=v0.4.0\nRELEASED=no\n' >"$S/state"

	git init --bare -q "$S/origin.git"
	git init -q -b main "$S/local"
	git -C "$S/local" config user.name Tester
	git -C "$S/local" config user.email tester@example.com
	git -C "$S/local" config commit.gpgsign false
	printf 'changelog:\n  categories:\n    - title: Features\n      labels: ["enhancement"]\n' \
		>"$S/local/.github/release.yml"
	printf '# test\n' >"$S/local/README.md"
	git -C "$S/local" add .
	git -C "$S/local" commit -q -m 'chore: initial commit'
	git -C "$S/local" tag -a v0.3.0 -m v0.3.0
	git -C "$S/local" remote add origin "$S/origin.git"
	git -C "$S/local" push -q -u origin main
	git -C "$S/local" checkout -q -b develop
	git -C "$S/local" push -q -u origin develop
	printf 'feature\n' >"$S/local/feature.txt"
	git -C "$S/local" add .
	git -C "$S/local" commit -q -m 'feat: add feature'
	printf 'fix\n' >"$S/local/fix.txt"
	git -C "$S/local" add .
	git -C "$S/local" commit -q -m 'fix: correct bug'
	git -C "$S/local" push -q origin develop
	state_set CI_SHA "$(git -C "$S/local" rev-parse --short HEAD)"

	cat >"$S/bin/gh" <<'GH'
#!/bin/sh
set -eu
get() { grep "^$1=" "$GH_STATE" 2>/dev/null | cut -d= -f2- | head -n 1 || true; }
setv() { grep -v "^$1=" "$GH_STATE" >"$GH_STATE.next" 2>/dev/null || true; printf '%s=%s\n' "$1" "$2" >>"$GH_STATE.next"; mv "$GH_STATE.next" "$GH_STATE"; }
case "$*" in
  *"repo view"*) printf 'MatiasOlivera/ubuntu-config\n' ;;
  *"generate-notes"*) setv API_ARGS "$*"; printf '## What Changed\n- grouped note\n' ;;
  *"run list"*) printf '%s %s\n' "$(get CI)" "$(get CI_SHA)" ;;
  *"pr create"*)
    title='' body='' labels=''; prev=''
    for arg in "$@"; do
      [ "$prev" = "--title" ] && title=$arg
      [ "$prev" = "--body" ] && body=$arg
      [ "$prev" = "--label" ] && labels=$arg
      prev=$arg
    done
    setv PR_NUMBER 10; setv PR_TITLE "$title"; setv PR_BODY "$body"; setv PR_LABELS "$labels"
    printf 'https://github.com/MatiasOlivera/ubuntu-config/pull/10\n' ;;
  *"pr edit"*)
    prev=''
    for arg in "$@"; do
      [ "$prev" = "--add-label" ] && setv RESTAMP_LABEL "$arg"
      prev=$arg
    done
    setv RESTAMP yes ;;
  *"pr list"*)
    [ -n "$(get PR_NUMBER)" ] && printf '%s\n' "$(get PR_NUMBER)" ;;
  *"pr view"*)
    case "$*" in
      *state*) printf 'MERGED\n' ;;
      *mergeCommit*) printf '%s\n' "$(get MERGE)" ;;
      *) printf '{}\n' ;;
    esac ;;
  *"release view"*) [ "$(get RELEASED)" = yes ] ;;
  *"release create"*)
    prev=''
    for arg in "$@"; do
      if [ "$prev" = "--notes-file" ] && [ -f "$arg" ]; then
        setv PUBLISHED_BODY "$(tr '\n' '|' <"$arg")"
      fi
      prev=$arg
    done
    setv CREATE_ARGS "$*"; setv RELEASED yes ;;
  *) printf 'unexpected gh call: %s\n' "$*" >&2; exit 1 ;;
esac
GH
	chmod +x "$S/bin/gh"

	cat >"$S/bin/git-cliff" <<'CLIFF'
#!/bin/sh
set -eu
get() { grep "^$1=" "$CLIFF_STATE" 2>/dev/null | cut -d= -f2- | head -n 1 || true; }
case "$*" in
  *"--bumped-version"*) printf '%s\n' "$(get VERSION)" ;;
  *)
    out=''; prev=''
    for arg in "$@"; do
      [ "$prev" = "-o" ] && out=$arg
      prev=$arg
    done
    [ -z "$out" ] && exit 0
    ver=$(get VERSION)
    printf '# Changelog\n\n## [%s] - 2026-11-25\n\n### Added\n- feat: add feature\n' "${ver#v}" >"$out"
    ;;
esac
CLIFF
	chmod +x "$S/bin/git-cliff"
}

run_release() {
	(
		cd "$S/local" || exit 1
		PATH="$S/bin:$PATH" GH_STATE="$S/state" CLIFF_STATE="$S/state" \
			GIT_CLIFF="$S/bin/git-cliff" GH_TOKEN=stub \
			bash "$RELEASE_SH" "$@"
	)
}

# Stage the prepared release commit, then promote develop with a merge commit.
promote() {
	git -C "$S/local" checkout -q develop
	if [ ! -f "$S/local/CHANGELOG.md" ]; then
		printf '# Changelog\n\n## [0.4.0] - 2026-11-25\n' >"$S/local/CHANGELOG.md"
		git -C "$S/local" add .
		git -C "$S/local" commit -q -m 'chore(release): v0.4.0'
		git -C "$S/local" push -q origin develop
		state_set CI_SHA "$(git -C "$S/local" rev-parse --short HEAD)"
	fi
	state_set PR_NUMBER 10
	git -C "$S/local" checkout -q main
	git -C "$S/local" merge -q --no-ff -m 'Merge pull request #10 from develop' develop
	git -C "$S/local" push -q origin main
	state_set MERGE "$(git -C "$S/local" rev-parse --short HEAD)"
}

expect_failure() {
	local name=$1 output
	if output=$(run_release "${@:2}" 2>&1); then
		fail "$name: expected non-zero exit, got success"
		printf '%s\n' "$output" >&2
	elif printf '%s\n' "$output" | grep -q '^release:'; then
		ok "$name: refused"
	else
		fail "$name: failed without a release guard message"
		printf '%s\n' "$output" >&2
	fi
}

expect_success() {
	local name=$1 output
	if output=$(run_release "${@:2}" 2>&1); then
		printf '%s\n' "$output" >>"$S/log"
		ok "$name"
	else
		fail "$name: unexpected failure"
		printf '%s\n' "$output" >&2
	fi
}

assert_eq() {
	if [ "$2" = "$3" ]; then
		ok "$1"
	else
		fail "$1: expected '$2', got '$3'"
	fi
}

assert_contains() {
	case "$2" in
	*"$3"*) ok "$1" ;;
	*) fail "$1: '$2' does not contain '$3'" ;;
	esac
}

# --- prepare ---------------------------------------------------------------

test_prepare_refuses_wrong_branch() {
	setup
	git -C "$S/local" checkout -q -b chore/other develop
	expect_failure 'prepare wrong branch' prepare
	local tags
	tags=$(git -C "$S/local" tag --list | wc -l)
	assert_eq 'wrong branch leaves tags alone' 1 "$tags"
}

test_prepare_refuses_dirty_tree() {
	setup
	printf 'uncommitted\n' >>"$S/local/README.md"
	expect_failure 'prepare dirty tree' prepare
	assert_eq 'dirty tree opens no PR' '' "$(state_get PR_NUMBER)"
}

test_prepare_refuses_existing_tag() {
	setup
	git -C "$S/local" tag -a v0.4.0 -m v0.4.0
	expect_failure 'prepare existing tag' prepare
	assert_eq 'existing tag keeps changelog absent' no "$(test -f "$S/local/CHANGELOG.md" && echo yes || echo no)"
}

test_prepare_refuses_red_ci() {
	setup
	state_set CI failure
	expect_failure 'prepare red CI' prepare
	assert_eq 'red CI opens no PR' '' "$(state_get PR_NUMBER)"
}

test_prepare_creates_release_commit_and_pr() {
	setup
	expect_success 'prepare on green develop' prepare
	assert_eq 'promotion PR opened' 10 "$(state_get PR_NUMBER)"
	assert_eq 'created promotion PR carries release label' release "$(state_get PR_LABELS)"
	assert_eq 'changelog committed' 0.4.0 "$(git -C "$S/local" show HEAD:CHANGELOG.md | sed -nE 's/^## \[([^]]+)\].*/\1/p')"
	assert_eq 'tag not created by prepare' 1 "$(git -C "$S/local" tag --list | wc -l)"
	assert_eq 'release not created by prepare' no "$(state_get RELEASED)"
}

test_prepare_restamps_open_pr() {
	setup
	state_set PR_NUMBER 10
	expect_success 'prepare re-stamps open PR' prepare
	assert_eq 'open PR edited, not recreated' yes "$(state_get RESTAMP)"
	assert_eq 're-stamped PR keeps release label' release "$(state_get RESTAMP_LABEL)"
}

# --- preview ----------------------------------------------------------------

test_preview_is_read_only() {
	setup
	expect_success 'preview on develop' preview
	assert_contains 'preview prints generated notes' "$(cat "$S/log")" 'grouped note'
	assert_contains 'preview prints version' "$(cat "$S/log")" 'v0.4.0'
	assert_eq 'preview creates no tag' 1 "$(git -C "$S/local" tag --list | wc -l)"
	assert_eq 'preview leaves no changelog' no "$(test -f "$S/local/CHANGELOG.md" && echo yes || echo no)"
	assert_eq 'preview issues no release call' '' "$(state_get CREATE_ARGS)"
	assert_contains 'preview targets develop' "$(state_get API_ARGS)" 'target_commitish=develop'
}

test_preview_warns_on_unpromoted_config() {
	setup
	printf 'changelog:\n  categories:\n    - title: Other\n      labels: ["*"]\n' \
		>"$S/local/.github/release.yml"
	git -C "$S/local" add . && git -C "$S/local" commit -q -m 'docs: change grouping'
	git -C "$S/local" push -q origin develop
	expect_success 'preview with divergent config' preview
	assert_contains 'divergence warning names target' "$(cat "$S/log")" 'main'
}

# --- publish ----------------------------------------------------------------

test_publish_refuses_squash_merge() {
	setup
	git -C "$S/local" checkout -q main
	printf 'squash\n' >"$S/local/squash.txt"
	git -C "$S/local" add . && git -C "$S/local" commit -q -m 'chore(release): v0.4.0'
	git -C "$S/local" push -q origin main
	state_set MERGE "$(git -C "$S/local" rev-parse --short HEAD)"
	state_set PR_NUMBER 10
	git -C "$S/local" checkout -q develop
	expect_failure 'publish refuses squash merge' publish
	assert_eq 'squash merge leaves no release' no "$(state_get RELEASED)"
}

test_publish_refuses_red_ci() {
	setup
	promote
	state_set CI failure
	expect_failure 'publish refuses red CI' publish
	assert_eq 'red CI leaves no tag' 1 "$(git -C "$S/local" tag --list | wc -l)"
}

test_publish_refuses_version_mismatch() {
	setup
	state_set VERSION v0.5.0
	promote
	expect_failure 'publish refuses version mismatch' publish
	assert_eq 'mismatch leaves no release' no "$(state_get RELEASED)"
}

test_publish_tags_merges_and_publishes() {
	setup
	promote
	expect_success 'publish on promotion merge' publish
	local merge tag_peel
	merge="$(state_get MERGE)"
	tag_peel=$(git -C "$S/local" rev-parse 'v0.4.0^{commit}' | cut -c1-7)
	assert_eq 'tag peels to merge commit' "$merge" "$tag_peel"
	assert_eq 'release published' yes "$(state_get RELEASED)"
	assert_contains 'release body comes from API' "$(state_get PUBLISHED_BODY)" 'grouped note'
	assert_contains 'release verifies tag' "$(state_get CREATE_ARGS)" '--verify-tag'
	assert_contains 'release targets merge' "$(state_get CREATE_ARGS)" "--target $merge"
	git -C "$S/local" fetch -q origin develop
	if git -C "$S/local" merge-base --is-ancestor v0.4.0 origin/develop; then
		ok 'tag reachable from develop'
	else
		fail 'tag reachable from develop'
	fi
}

test_publish_resumes_existing_tag() {
	setup
	promote
	git -C "$S/local" tag -a v0.4.0 -m v0.4.0 "$(state_get MERGE)"
	git -C "$S/local" push -q origin v0.4.0
	expect_success 'publish resumes from existing tag' publish
	assert_eq 'resumed publish creates release' yes "$(state_get RELEASED)"
}

test_publish_refuses_foreign_tag() {
	setup
	promote
	git -C "$S/local" tag -a v0.4.0 -m v0.4.0 HEAD~1
	expect_failure 'publish refuses foreign tag' publish
	assert_eq 'foreign tag leaves no release' no "$(state_get RELEASED)"
}

# --- pinned tool and workflow ----------------------------------------------

test_tool_checksum_guard() {
	setup
	if [ ! -f "$TOOL_SH" ]; then
		fail 'checksum guard: helper missing'
		return
	fi
	printf 'archive' >"$S/archive.tar.gz"
	printf 'deadbeef  archive.tar.gz\n' >"$S/bad.sha512"
	if (cd "$S" && bash "$TOOL_SH" --selftest-verify archive.tar.gz bad.sha512) >/dev/null 2>&1; then
		fail 'checksum guard accepted a bad checksum'
	else
		ok 'checksum guard rejects bad checksum'
	fi
}

test_workflow_contract() {
	setup
	if [ ! -f "$WORKFLOW" ]; then
		fail 'workflow contract: file missing'
		return
	fi
	local wf
	wf=$(cat "$WORKFLOW")
	assert_contains 'workflow triggers on closed PR' "$wf" 'types: [closed]'
	assert_contains 'workflow limits base to main' "$wf" 'branches: [main]'
	assert_contains 'workflow grants tag permission' "$wf" 'contents: write'
	assert_contains 'workflow invokes publish' "$wf" 'publish'
}

test_notes_exclude_release_label() {
	setup
	if grep -qE '^[[:space:]]*- release$' "$ROOT/.github/release.yml"; then
		ok 'release label stays excluded from generated notes'
	else
		fail 'release label no longer excluded from generated notes'
	fi
}

test_prepare_refuses_wrong_branch
test_prepare_refuses_dirty_tree
test_prepare_refuses_existing_tag
test_prepare_refuses_red_ci
test_prepare_creates_release_commit_and_pr
test_prepare_restamps_open_pr
test_preview_is_read_only
test_preview_warns_on_unpromoted_config
test_publish_refuses_squash_merge
test_publish_refuses_red_ci
test_publish_refuses_version_mismatch
test_publish_tags_merges_and_publishes
test_publish_resumes_existing_tag
test_publish_refuses_foreign_tag
test_tool_checksum_guard
test_workflow_contract
test_notes_exclude_release_label

printf '%d case(s), %d failure(s), %d skipped\n' "$CASES" "$FAILED" "$SKIPPED"
[ "$FAILED" -eq 0 ]
