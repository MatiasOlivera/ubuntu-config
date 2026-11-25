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

die() {
	echo "release: $1" >&2
	exit 1
}

cliff() {
	sh "$TOOL" "$@"
}

repo_slug() {
	if [ -n "${GITHUB_REPOSITORY:-}" ]; then
		printf '%s\n' "$GITHUB_REPOSITORY"
	else
		gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || die "cannot resolve the GitHub repository"
	fi
}

develop_check() {
	line=$(gh run list --branch develop --limit 1 --json conclusion,headSha \
		-q '.[0] | "\(.conclusion) \(.headSha)"' 2>/dev/null || echo 'none ')
	conclusion=${line%% *}
	sha=${line#* }
	[ "$conclusion" = success ] || die "latest CI run on develop is not green (conclusion: $conclusion)"
	if [ -n "$sha" ]; then
		case "$(git rev-parse HEAD)" in
		"$sha"*) ;;
		*) die "latest CI run on develop is not for the current tip" ;;
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

	cliff --tag "$version" -o CHANGELOG.md
	[ -s CHANGELOG.md ] || die "changelog generation produced an empty file"

	body=$(cat <<EOF
## What & why

Promote \`develop\` to \`main\` for release $version. The version and exhaustive
changelog were generated from the unreleased Conventional Commits.

## Changes

- \`CHANGELOG.md\`: stamped \`$version\`

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
		gh pr edit "$open_pr" --body "$body" >/dev/null
		echo "release: $version re-stamped in promotion PR #$open_pr"
	else
		gh pr create --base main --head develop --title "chore(release): $version" \
			--body "$body" >/dev/null
		echo "release: $version prepared; merge the promotion PR to publish"
	fi
}

usage() {
	printf 'usage: %s <prepare|preview|publish>\n' "$0" >&2
	exit 1
}

[ $# -eq 1 ] || usage
case "$1" in
prepare) prepare ;;
*) usage ;;
esac
