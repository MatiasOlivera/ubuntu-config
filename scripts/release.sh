#!/bin/sh
# Release entry point: prepare on develop, preview locally, publish from the
# promotion workflow. ADR 0016 documents the decisions behind the sequence.
set -eu

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
if ! ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
	ROOT=$(cd "$SELF_DIR/.." && pwd)
fi
cd "$ROOT"

TOOL="$SELF_DIR/git-cliff.sh"

NOTES=''
WT=''
WT_PARENT=''

die() {
	echo "release: $1" >&2
	exit 1
}

publish_cleanup() {
	[ -z "$NOTES" ] || rm -f "$NOTES"
	[ -z "$WT" ] || git worktree remove --force "$WT" >/dev/null 2>&1 || true
	[ -z "$WT_PARENT" ] || rm -rf "$WT_PARENT"
	return 0
}

cliff() {
	sh "$TOOL" --config "$SELF_DIR/../cliff.toml" "$@"
}

previous_tag() {
	tag=$(git describe --tags --abbrev=0 "$1" 2>/dev/null || true)
	[ -n "$tag" ] || tag=$(git tag --list 'v[0-9]*' --sort=-v:refname 2>/dev/null | head -n 1)
	printf '%s\n' "$tag"
}

write_changelog() {
	cliff --tag "$1" -o "$2"
}

write_excerpt() {
	version=$1
	out=$2
	previous=$(previous_tag HEAD)
	if [ -n "$previous" ]; then
		cliff "$previous..HEAD" --tag "$version" -o "$out"
	else
		cliff --tag "$version" -o "$out"
	fi
}

notes_at() {
	version=$1
	target=$2
	previous=$3
	if [ -n "$previous" ]; then
		gh api "repos/$repo/releases/generate-notes" \
			-f tag_name="$version" -f previous_tag_name="$previous" \
			-f target_commitish="$target" --jq .body 2>/dev/null
	else
		gh api "repos/$repo/releases/generate-notes" \
			-f tag_name="$version" -f target_commitish="$target" --jq .body 2>/dev/null
	fi
}

repo_slug() {
	if [ -n "${GITHUB_REPOSITORY:-}" ]; then
		printf '%s\n' "$GITHUB_REPOSITORY"
	else
		gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || die "cannot resolve the GitHub repository"
	fi
}

develop_check() {
	expected=${1:-$(git rev-parse HEAD)}
	line=$(gh run list --workflow test --branch develop --limit 1 --json conclusion,headSha \
		-q '.[0] | "\(.conclusion) \(.headSha)"' 2>/dev/null || echo 'none ')
	conclusion=${line%% *}
	sha=${line#* }
	[ "$conclusion" = success ] || die "latest CI run on develop is not green (conclusion: $conclusion)"
	if [ -n "$sha" ]; then
		case "$expected" in
		"$sha"*) ;;
		*) die "latest CI run on develop is not for the release commit" ;;
		esac
	fi
}

refuse_existing_tag() {
	version=$1
	git rev-parse -q --verify "refs/tags/$version" >/dev/null &&
		die "tag $version already exists locally"
	git ls-remote --exit-code --tags origin "refs/tags/$version" >/dev/null 2>&1 &&
		die "tag $version already exists on origin"
	return 0
}

prepare() {
	branch=$(git branch --show-current)
	[ "$branch" = develop ] || die "prepare must run on develop (on $branch)"
	[ -z "$(git status --porcelain)" ] || die "working tree is not clean"

	git fetch origin --quiet --tags
	ahead=$(git rev-list --count origin/develop..HEAD)
	behind=$(git rev-list --count HEAD..origin/develop)
	[ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ] || die "develop is not synced with origin"
	[ "$(git rev-list --count origin/main..origin/develop)" -gt 0 ] ||
		die "develop has nothing ahead of main; nothing to release"

	develop_check

	version=$(cliff --bumped-version)
	case "$version" in
	v[0-9]*) ;;
	*) die "computed version is not a v-prefixed tag: $version" ;;
	esac
	refuse_existing_tag "$version"

	write_changelog "$version" CHANGELOG.md
	[ -s CHANGELOG.md ] || die "changelog generation produced an empty file"

	body=$(cat <<EOF
## What & why

Promote \`develop\` to \`main\` for release $version. The version was computed
from the unreleased Conventional Commits.

## Changes

- \`CHANGELOG.md\`: regenerated with the full history, stamped \`$version\`

## Verification

- [x] Checks on develop are green
- [ ] The changelog in this diff reads correctly
- [ ] Merged with a merge commit; publication then happens automatically

Release notes on the release page are generated from the target ref, so the
grouping configuration must already be on \`main\` to take effect.
EOF
	)

	git add CHANGELOG.md
	if git diff --cached --quiet; then
		git commit -q --allow-empty -m "chore(release): $version"
	else
		git commit -q -m "chore(release): $version"
	fi
	git push origin develop

	open_pr=$(gh pr list --base main --head develop --state open --json number \
		-q '.[0].number // empty' 2>/dev/null || echo '')
	if [ -n "$open_pr" ]; then
		gh pr edit "$open_pr" --body "$body" --add-label release >/dev/null
		echo "release: $version re-stamped in promotion PR #$open_pr"
	else
		gh pr create --base main --head develop --title "chore(release): $version" \
			--body "$body" --label release >/dev/null
		echo "release: $version prepared; merge the promotion PR to publish"
	fi
}

preview() {
	branch=$(git branch --show-current)
	[ "$branch" = develop ] || die "preview must run on develop (on $branch)"

	git fetch origin --quiet --tags
	version=$(cliff --bumped-version)
	previous=$(previous_tag HEAD)

	dev_config=$(git show HEAD:.github/release.yml 2>/dev/null || echo '')
	main_config=$(git show origin/main:.github/release.yml 2>/dev/null || echo '')
	if [ "$dev_config" != "$main_config" ]; then
		echo "warning: notes configuration differs on develop and main; the release target main would use its own grouping"
	fi

	notes=$(mktemp "${TMPDIR:-/tmp}/release-notes.XXXXXX") || die "cannot create temp file"
	trap 'rm -f "$notes"' EXIT
	write_excerpt "$version" "$notes"

	repo=$(repo_slug)
	body=$(notes_at "$version" develop "$previous") ||
		die "generated-notes request failed"

	printf 'version: %s\n' "$version"
	printf 'changelog section:\n'
	awk '/^## / { if (shown) exit; shown = 1 } shown { print }' "$notes"
	printf 'generated notes (projected against develop; publication regenerates at main):\n'
	printf '%s\n' "$body"
}

publish() {
	branch=$(git branch --show-current)
	[ "$branch" = main ] || die "publish must run on main (on $branch)"

	git fetch origin --quiet --tags
	pr=$(gh pr list --base main --head develop --state merged --json number \
		-q '.[0].number // empty' 2>/dev/null || echo '')
	[ -n "$pr" ] || die "no merged develop to main pull request found"
	state=$(gh pr view "$pr" --json state -q .state 2>/dev/null || echo '')
	[ "$state" = MERGED ] || die "promotion PR #$pr is not merged (state: $state)"
	merge=$(gh pr view "$pr" --json mergeCommit -q .mergeCommit.oid 2>/dev/null || echo '')
	[ -n "$merge" ] || die "promotion PR #$pr was not merged with a merge commit"
	merge_commit=$(git rev-parse "$merge^{commit}")
	git merge-base --is-ancestor "$merge_commit" origin/main ||
		die "promotion commit $merge is not on main"
	[ "$(git rev-list --parents -n 1 "$merge_commit" | wc -w)" -eq 3 ] ||
		die "$merge is not a two-parent merge commit"
	release_commit=$(git rev-parse "$merge_commit^2")
	git merge-base --is-ancestor "$release_commit" origin/develop ||
		die "release commit is not on develop"

	version=$(cliff --bumped-version)
	cl_version=$(git show "$merge_commit:CHANGELOG.md" 2>/dev/null |
		sed -nE 's/^## \[([^]]+)\].*/\1/p' | head -n 1)
	[ "v$cl_version" = "$version" ] ||
		die "changelog version ($cl_version) does not match computed version ($version)"
	previous=$(previous_tag "$merge_commit")
	develop_check "$release_commit"

	if git rev-parse -q --verify "refs/tags/$version" >/dev/null; then
		[ "$(git rev-parse "$version^{commit}")" = "$merge_commit" ] ||
			die "tag $version points at another commit; refusing to overwrite it"
	else
		git tag -a "$version" "$merge_commit" -m "Release $version"
	fi
	if ! git ls-remote --exit-code --tags origin "refs/tags/$version" >/dev/null 2>&1; then
		git push origin "$version"
	fi

	trap 'publish_cleanup' EXIT
	trap 'exit 130' INT HUP
	repo=$(repo_slug)
	NOTES=$(mktemp "${TMPDIR:-/tmp}/release-notes.XXXXXX") || die "cannot create temp file"
	body=$(notes_at "$version" "$merge_commit" "$previous") ||
		die "generated-notes request failed"
	printf '%s\n' "$body" >"$NOTES"
	printf 'release notes for %s at %s:\n%s\n' "$version" "$merge" "$body"

	if ! git merge-base --is-ancestor "$merge_commit" origin/develop; then
		WT_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/release-merge.XXXXXX") ||
			die "cannot create temp directory"
		WT="$WT_PARENT/develop"
		git worktree add --detach -q "$WT" origin/develop
		(
			cd "$WT" || exit 1
			git merge -q --no-edit "$merge_commit" ||
				die "failed to merge main back into develop; resolve conflicts"
			git push -q origin HEAD:refs/heads/develop
		)
		git worktree remove --force "$WT" >/dev/null 2>&1 || true
		WT=''
	fi

	if gh release view "$version" >/dev/null 2>&1; then
		echo "release: $version already published; nothing left to resume"
		exit 0
	fi
	gh release create "$version" --target "$merge_commit" \
		--notes-file "$NOTES" --verify-tag >/dev/null
	echo "release: $version published at $merge, merged back to develop, PR #$pr"
}

usage() {
	printf 'usage: %s <prepare|preview|publish>\n' "$0" >&2
	exit 1
}

[ $# -eq 1 ] || usage
case "$1" in
prepare) prepare ;;
preview) preview ;;
publish) publish ;;
*) usage ;;
esac
