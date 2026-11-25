#!/bin/sh
# Resolve a pinned git-cliff, verified against the publisher's checksum.
# GIT_CLIFF overrides resolution so hermetic tests never download anything.
set -eu

VERSION=2.14.2
ARCHIVE="git-cliff-${VERSION}-x86_64-unknown-linux-gnu.tar.gz"
BASE="https://github.com/orhun/git-cliff/releases/download/v${VERSION}"

die() {
	echo "git-cliff: $1" >&2
	exit 1
}

verify_archive() {
	archive=$1
	checksum=$2
	(
		cd "$(dirname "$archive")" || exit 1
		sha512sum -c "$(basename "$checksum")" >/dev/null 2>&1
	)
}

case "${1:-}" in
--selftest-verify)
	[ $# -eq 3 ] || die "usage: $0 --selftest-verify <archive> <checksum>"
	verify_archive "$2" "$3" || die "checksum mismatch for $2"
	exit 0
	;;
esac

if [ -n "${GIT_CLIFF:-}" ]; then
	[ -x "$GIT_CLIFF" ] || die "GIT_CLIFF is not executable: $GIT_CLIFF"
	exec "$GIT_CLIFF" "$@"
fi

for cmd in curl sha512sum tar; do
	command -v "$cmd" >/dev/null 2>&1 || die "$cmd is required to install git-cliff $VERSION"
done

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/ubuntu-config/git-cliff/$VERSION"
if [ -x "$CACHE/git-cliff" ]; then
	exec "$CACHE/git-cliff" "$@"
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/git-cliff.XXXXXX") || die "cannot create temp directory"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$BASE/$ARCHIVE" -o "$TMP/$ARCHIVE" || die "download failed: $ARCHIVE"
curl -fsSL "$BASE/$ARCHIVE.sha512" -o "$TMP/$ARCHIVE.sha512" || die "checksum download failed"
verify_archive "$TMP/$ARCHIVE" "$TMP/$ARCHIVE.sha512" || die "checksum mismatch for $ARCHIVE"
tar -xzf "$TMP/$ARCHIVE" -C "$TMP" || die "extraction failed"
BIN=$(find "$TMP" -type f -name git-cliff -perm -u+x | head -n 1)
[ -n "$BIN" ] || die "no git-cliff binary in $ARCHIVE"
mkdir -p "$CACHE"
cp "$BIN" "$CACHE/git-cliff"
chmod 755 "$CACHE/git-cliff"
exec "$CACHE/git-cliff" "$@"
