#!/bin/sh
#
# remove-link.sh — remove one of our symlinks, and only ours.
#
# usage: remove-link.sh <target> <link>
#
#   target  the path the link must still point at for us to claim it; absolute,
#           and never DESTDIR-prefixed
#   link    where the link is: absolute, and DESTDIR-prefixed by the caller
#
# environment:
#   DRY_RUN  non-empty: report what would be removed, remove nothing
#
# The target is what makes this safe: a link we installed and the user has
# since repointed is theirs now, and an ordinary file at the same path was
# never ours at all.  Both are left alone and reported, so uninstall stays
# bounded by the declaration rather than by the path.
#
set -eu

target=${1:?usage: remove-link.sh <target> <link>}
link=${2:?usage: remove-link.sh <target> <link>}

: "${DRY_RUN:=}"

if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
	if [ -n "$DRY_RUN" ]; then
		printf 'would remove link %s\n' "$link"
	else
		rm -f "$link"
		printf 'removed link %s\n' "$link"
	fi
elif [ -e "$link" ] || [ -L "$link" ]; then
	printf 'not ours       %s\n' "$link"
else
	printf 'not installed  %s\n' "$link"
fi
