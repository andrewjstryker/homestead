#!/bin/sh
set -eu
here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
export HOMESTEAD_MK=$root/homestead.mk
export HOME=$work/home XDG_CONFIG_HOME=$work/config XDG_DATA_HOME=$work/data
export XDG_STATE_HOME=$work/state XDG_CACHE_HOME=$work/cache BIN_DIR=$work/bin
module=$work/module
mkdir -p "$module/src/config/empty" "$module/vendor/data/empty"
printf ignored > "$module/src/config/empty/.keep"
printf plain > "$module/src/config/plain"
printf 'M4_VALUE\n' > "$module/src/config/rendered.m4"
cat > "$module/Build.mk" <<'MAKEFILE'
required_inputs = VALUE
claimed_outputs = stage/config/generated/one stage/config/generated/two
include ${HOMESTEAD_MK}

# Target-specific input must remain visible during preflight, even with -f.
check: VALUE = configured

${claimed_outputs}:
	test -d '$(@D)'
	printf generated > '$@'
	printf '%s\n' '$@' >> builds
MAKEFILE
run() { make --no-print-directory -j4 -C "$module" -f Build.mk "$@"; }
run check
test ! -e "$module/stage"
if run stage VALUE= > "$work/missing" 2>&1; then
    printf 'missing input allowed directory creation\n' >&2
    exit 1
fi
test ! -e "$module/stage"
run stage VALUE=first RSYNC=
test -d "$module/stage/config/empty"
test "$(cat "$module/stage/config/rendered")" = first
test "$(wc -l < "$module/builds")" -eq 2
# Directory mtime changes do not rebuild current outputs.
touch "$module/stage/config/generated"
run stage VALUE=first
test "$(wc -l < "$module/builds")" -eq 2
# Pruning must preserve an existing empty output parent while Make rebuilds files.
rm "$module/stage/config/generated/one" "$module/stage/config/generated/two"
run stage VALUE=second
test "$(wc -l < "$module/builds")" -eq 4
test "$(cat "$module/stage/config/rendered")" = second
# Recreate a missing declared empty directory and prune obsolete public state.
rmdir "$module/stage/config/empty"
printf stale > "$module/stage/config/stale"
run stage VALUE=second
test -d "$module/stage/config/empty"
test ! -e "$module/stage/config/stale"
# Dry-run installation must not create receipt directories or destination roots.
run install VALUE=second DRY_RUN=1 > "$work/dry-run"
test ! -e "$module/.homestead"
test ! -e "$XDG_CONFIG_HOME"
run install VALUE=second > "$work/install"
test -f "$module/.homestead/receipt"
test -d "$XDG_CONFIG_HOME/empty"
test -d "$XDG_DATA_HOME/empty"
# Ordinary m4 flags are module-owned and still invalidate rendered outputs.
run stage VALUE=second m4_flags='--prefix-builtins'
grep -q '^ *m4_flags=--prefix-builtins$' "$module/stage/.build/m4-context"
printf 'dependency graph: PASS\n'
