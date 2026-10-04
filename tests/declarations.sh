#!/bin/sh
set -eu
here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
export HOMESTEAD_MK=$root/homestead.mk
export HOME=$work/home XDG_CONFIG_HOME=$work/config XDG_DATA_HOME=$work/data
export XDG_STATE_HOME=$work/state XDG_CACHE_HOME=$work/cache BIN_DIR=$work/bin

fixture() {
    module=$work/$1
    mkdir -p "$module/src/config" "$module/vendor/config" "$module/stage/.build"
    printf 'keep until validation succeeds\n' > "$module/stage/stale"
    printf 'unchanged context\n' > "$module/stage/.build/m4-context"
    cat > "$module/Makefile" <<'MAKEFILE'
include ${HOMESTEAD_MK}
MAKEFILE
}
reject() {
    expected=$1
    for target in check check-declarations check-stage-tools stage preview install; do
        if make --no-print-directory -j4 -C "$module" "$target" >"$work/output" 2>&1; then
            printf 'expected %s to reject %s\n' "$target" "$module" >&2
            exit 1
        fi
        grep -Fq "$expected" "$work/output"
        test "$(cat "$module/stage/stale")" = 'keep until validation succeeds'
        test "$(cat "$module/stage/.build/m4-context")" = 'unchanged context'
        test ! -e "$XDG_CONFIG_HOME"
        test ! -e "$module/.homestead/receipt"
        test ! -e "$module/transformed"
    done
    # Ambiguous declarations do not prevent read-only diagnostics or cleanup.
    make --no-print-directory -C "$module" help >"$work/help"
    make --no-print-directory -C "$module" show >"$work/show"
    make --no-print-directory -C "$module" clean
}

fixture plain-template
printf plain > "$module/src/config/example"
printf rendered > "$module/src/config/example.m4"
reject 'Duplicate manifest files: config/example'

fixture claimed-ordinary
printf plain > "$module/src/config/example"
cat > "$module/Makefile" <<'MAKEFILE'
claimed_outputs = ${stage}/config/example
include ${HOMESTEAD_MK}
${stage}/config/example:
	touch transformed
MAKEFILE
reject 'Duplicate manifest files: config/example'

fixture claimed-claimed
cat > "$module/Makefile" <<'MAKEFILE'
claimed_outputs = ${stage}/config/example ${stage}/config/example
include ${HOMESTEAD_MK}
${stage}/config/example:
	touch transformed
MAKEFILE
reject 'Duplicate manifest files: config/example'

fixture staged-vendor
printf plain > "$module/src/config/example"
printf vendored > "$module/vendor/config/example"
reject 'Duplicate manifest files: config/example'

fixture ancestor
printf file > "$module/src/config/parent"
mkdir -p "$module/vendor/config/parent/nested"
printf child > "$module/vendor/config/parent/nested/child"
reject 'Manifest paths declared as both file and directory: config/parent'

fixture reverse-ancestor
mkdir -p "$module/src/config/parent/nested"
printf child > "$module/src/config/parent/nested/child"
printf file > "$module/vendor/config/parent"
reject 'Manifest paths declared as both file and directory: config/parent'

fixture empty-directory
printf rendered > "$module/src/config/parent.m4"
mkdir -p "$module/src/config/parent/empty"
printf private > "$module/src/config/parent/empty/.keep"
reject 'Manifest paths declared as both file and directory: config/parent'

# Distinct declarations can share directories; private/unmapped vendor files
# do not enter validation. Claimed sources are excluded from ordinary mapping.
fixture valid
mkdir -p "$module/vendor/build" "$module/vendor/config/.private"
printf generated > "$module/src/config/plain"
printf transformed > "$module/src/config/custom.input"
printf vendored > "$module/vendor/config/other"
printf ignored > "$module/vendor/build/plain"
printf ignored > "$module/vendor/config/.private/plain"
cat > "$module/Makefile" <<'MAKEFILE'
claimed_sources = ${src}/config/custom.input
claimed_outputs = ${stage}/config/custom.input
include ${HOMESTEAD_MK}
${stage}/config/custom.input: ${src}/config/custom.input
	mkdir -p '$(@D)'
	cp '$<' '$@'
MAKEFILE
make --no-print-directory -C "$module" check-declarations M4= RSYNC=
make --no-print-directory -j4 -C "$module" install
test -f "$XDG_CONFIG_HOME/plain"
test -f "$XDG_CONFIG_HOME/custom.input"
test -f "$XDG_CONFIG_HOME/other"
test ! -e "$module/stage/stale"

# Uninstall trusts its receipt even if the current declaration becomes invalid.
printf collision > "$module/vendor/config/plain"
make --no-print-directory -C "$module" uninstall
test ! -e "$XDG_CONFIG_HOME/plain"
test ! -e "$XDG_CONFIG_HOME/custom.input"
test ! -e "$XDG_CONFIG_HOME/other"
printf 'declaration validation: PASS\n'
