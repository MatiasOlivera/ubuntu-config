#!/usr/bin/env bash
# [Architecture] Uses Template Method (partial)
# Shared apt source writer: overwrite one canonical source and prune the stale
# opposite-layout sibling plus any extra paths (old keys). Source-only, no apt
# update; the caller owns the source bytes and the single Signed-By in them.

apt_source_write() {
	local file=$1
	shift
	local stem=${file%.*} sibling=
	case $file in
		*.sources) sibling="$stem.list" ;;
		*.list) sibling="$stem.sources" ;;
	esac

	sudo tee "/etc/apt/sources.list.d/$file" >/dev/null
	if [[ -n $sibling ]]; then
		sudo rm -f "/etc/apt/sources.list.d/$sibling"
	fi
	local stale
	for stale in "$@"; do
		sudo rm -f "$stale"
	done
}
