#!/bin/sh
set -eu
here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
export HOMESTEAD_MK=$root/homestead.mk
export HOME=$work/home XDG_CONFIG_HOME=$work/config XDG_DATA_HOME=$work/data
export XDG_STATE_HOME=$work/state XDG_CACHE_HOME=$work/cache BIN_DIR=$work/bin

mkdir -p "$work/module/src/config" "$work/module/stage/.build"
printf plain > "$work/module/src/config/example"
printf template > "$work/module/src/config/example.m4"
printf stale > "$work/module/stage/stale"
printf context > "$work/module/stage/.build/m4-context"
cat > "$work/module/Makefile" <<'MAKEFILE'
required_inputs = REQUIRED_VALUE
SYNC_TOOL ?= /bin/true
sync_tools = SYNC_TOOL
include ${HOMESTEAD_MK}
MAKEFILE

# Even parallel preflight reports independent failures without changing stage.
if make --no-print-directory -j4 -C "$work/module" check \
    REQUIRED_VALUE= M4= RSYNC= MD5SUM= SYNC_TOOL= >"$work/errors" 2>&1; then
    printf 'expected full preflight to fail\n' >&2
    exit 1
fi
for message in \
    'Duplicate manifest files: config/example' \
    'Missing required inputs needed to stage: REQUIRED_VALUE' \
    'Missing tools needed to stage: M4' \
    'Missing tools needed to install: RSYNC' \
    'Missing tools needed to uninstall: MD5SUM' \
    'Missing tools needed to sync: SYNC_TOOL'; do
    grep -Fq "$message" "$work/errors"
done
test "$(cat "$work/module/stage/stale")" = stale
test "$(cat "$work/module/stage/.build/m4-context")" = context
test ! -e "$work/module/stage/config"
test ! -e "$work/module/.homestead"
test ! -e "$XDG_CONFIG_HOME"

rm "$work/module/src/config/example.m4"
make --no-print-directory -C "$work/module" check REQUIRED_VALUE=provided
test -f "$work/module/stage/stale"
test "$(cat "$work/module/stage/.build/m4-context")" = context
test ! -e "$work/module/stage/config"
make --no-print-directory -j4 -C "$work/module" stage \
    REQUIRED_VALUE=provided RSYNC= MD5SUM= SYNC_TOOL=
test "$(cat "$work/module/stage/config/example")" = plain

# Collection check neither stages producers nor composes consumers, and reports
# failures in every selected module even with implicit discovery.
mkdir -p "$work/collection"
cp -R "$here/driver-fixture/base" "$here/driver-fixture/middle" \
    "$here/driver-fixture/zsh" "$work/collection/"
export HOMESTEAD_ROOT=$work/collection MODULES_FIRST=base MODULES_LAST=zsh
export CONFIG_ENV=$work/absent.env
"$root/home" check >"$work/check"
for module in base middle zsh; do
    test ! -e "$work/collection/$module/stage"
    test ! -e "$work/collection/$module/.homestead"
done
if RSYNC='' "$root/home" check >"$work/collection-errors" 2>&1; then
    printf 'expected all installation requirements to fail preflight\n' >&2
    exit 1
fi
grep -Fq 'FAILED (check): base middle zsh' "$work/collection-errors"
if REQUIRED_TOOL='' "$root/home" check >"$work/middle-error" 2>&1; then
    printf 'expected implicitly selected middle failure to fail preflight\n' >&2
    exit 1
fi
grep -Fq 'FAILED (check): middle' "$work/middle-error"
for module in base middle zsh; do
    test ! -e "$work/collection/$module/stage"
done
printf 'full preflight: PASS\n'
