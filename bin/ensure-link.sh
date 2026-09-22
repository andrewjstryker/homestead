#!/bin/sh
#
# ensure-link.sh — put one of our symlinks at a path, or refuse.
#
# usage: ensure-link.sh <target> <link>
#
#   target  what the link points at: an absolute path, and NEVER
#           DESTDIR-prefixed, because DESTDIR relocates where we write and not
#           what the configuration says
#   link    where the link goes: absolute, and DESTDIR-prefixed by the caller
#
# environment:
#   DRY_RUN  non-empty: report what would change, write nothing
#
# This is in a script rather than a recipe because it is a decision, not a
# command: three states with three different outcomes, and getting the wrong one
# wrong means replacing somebody's file.
#
#   already our link          nothing to do, and nothing to say
#   nothing there             create it (creating the parent if needed)
#   anything else             refuse, and exit non-zero
#
# "Anything else" includes a symlink pointing somewhere we did not point it,
# whether or not it dangles: a link at ~/.profile that we did not create is the
# user's, and replacing it is not ours to do.
#
# The refusal exits non-zero under DRY_RUN as well.  A dry run that noticed the
# collision, reported it, and exited 0 could not be used to gate the real run,
# which is most of what a dry run is for.
#
set -eu

target=${1:?usage: ensure-link.sh <target> <link>}
link=${2:?usage: ensure-link.sh <target> <link>}

: "${DRY_RUN:=}"

if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
	exit 0
fi

if [ -e "$link" ] || [ -L "$link" ]; then
	printf 'ensure-link: %s exists and is not our link\n' "$link" >&2
	printf 'ensure-link: refusing to replace it\n' >&2
	exit 1
fi

if [ -n "$DRY_RUN" ]; then
	printf 'would link %s -> %s\n' "$link" "$target"
else
	parent=$(dirname "$link")
	if [ ! -d "$parent" ]; then
		mkdir -p "$parent"
		chmod 0700 "$parent"
	fi
	ln -s "$target" "$link"
	printf 'linked %s -> %s\n' "$link" "$target"
fi
