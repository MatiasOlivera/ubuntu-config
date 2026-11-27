#!/usr/bin/env bash
# contract-check.sh — text-only checks for real source statements and guards.
# Files are read, never sourced or executed. Fail-closed.
# shellcheck disable=SC2016 # guard literal is shell text, not expanded here

set -u

mode=${1:?usage: contract-check.sh sourced|guard <files...>}
shift

status=0

case $mode in
sourced)
	if (($# < 3)); then
		printf 'usage: contract-check.sh sourced <install.sh> <post-install.sh> <library...>\n' >&2
		exit 2
	fi
	entries=("$1" "$2")
	shift 2
	# Only lines that actually source anything count; a filename in a comment
	# or string is not a source statement.
	sources="$(grep -E '^[[:space:]]*(source|\.)[[:space:]]+' "${entries[@]}")" || true
	for f in "$@"; do
		base=${f##*/}
		# shortcut: a trailing comment naming another file can still match;
		# tighten only if source lines start carrying end-of-line comments.
		if ! printf '%s\n' "$sources" | grep -qF -- "$base"; then
			printf 'not sourced: %s\n' "$f" >&2
			status=1
		fi
	done
	;;
guard)
	if (($# < 1)); then
		printf 'usage: contract-check.sh guard <config-script...>\n' >&2
		exit 2
	fi
	guard_re='^[[:space:]]*if \[\[ \$\{BASH_SOURCE\[0\]\} == "\$0" \]\]; then'
	for f in "$@"; do
		if ! grep -qE "$guard_re" "$f"; then
			printf 'standalone guard missing in %s\n' "$f" >&2
			status=1
		fi
	done
	;;
*)
	printf 'unknown mode: %s\n' "$mode" >&2
	exit 2
	;;
esac

exit "$status"
