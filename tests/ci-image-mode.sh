#!/usr/bin/env bash
# Choose how CI obtains the test image. "build" when the image definition
# changed in the PR, "pull" (the published image) otherwise.

ci_image_mode() {
	local base_ref="${1:-}"
	if [[ -n $base_ref ]]; then
		git fetch --depth=1 origin "$base_ref" >/dev/null 2>&1 || return 1
		if git diff --name-only FETCH_HEAD HEAD -- tests/Dockerfile tests/compose.yml | grep -q .; then
			printf 'build\n'
			return 0
		fi
	fi
	printf 'pull\n'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	ci_image_mode "${1:-}"
fi
