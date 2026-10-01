#!/bin/sh
set -eu
here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
export PROTOCOL_MK=$root/protocol.mk
export HOME=$work/home XDG_CONFIG_HOME=$work/config XDG_DATA_HOME=$work/data
export XDG_STATE_HOME=$work/state XDG_CACHE_HOME=$work/cache BIN_DIR=$work/bin

fixture() {
    concern=$work/$1
    mkdir -p "$concern/src/config" "$concern/vendor/config" "$concern/stage/.build"
    printf 'keep until validation succeeds\n' > "$concern/stage/stale"
    printf 'unchanged context\n' > "$concern/stage/.build/m4-context"
    cat > "$concern/Makefile" <<'MAKEFILE'
include ${PROTOCOL_MK}
MAKEFILE
}
reject() {
    expected=$1
    for target in check-declarations check-stage-tools stage preview install; do
        if make --no-print-directory -j4 -C "$concern" "$target" >"$work/output" 2>&1; then
            printf 'expected %s to reject %s\n' "$target" "$concern" >&2
            exit 1
        fi
        grep -Fq "$expected" "$work/output"
        test "$(cat "$concern/stage/stale")" = 'keep until validation succeeds'
        test "$(cat "$concern/stage/.build/m4-context")" = 'unchanged context'
        test ! -e "$XDG_CONFIG_HOME"
        test ! -e "$concern/.homestead/receipt"
        test ! -e "$concern/transformed"
    done
    # Ambiguous declarations do not prevent read-only diagnostics or cleanup.
    make --no-print-directory -C "$concern" help >"$work/help"
    make --no-print-directory -C "$concern" show >"$work/show"
    make --no-print-directory -C "$concern" clean
}

fixture plain-template
printf plain > "$concern/src/config/example"
printf rendered > "$concern/src/config/example.m4"
reject 'Duplicate manifest files: config/example'

fixture claimed-ordinary
printf plain > "$concern/src/config/example"
cat > "$concern/Makefile" <<'MAKEFILE'
claimed_outputs = ${stage}/config/example
include ${PROTOCOL_MK}
${stage}/config/example:
	touch transformed
MAKEFILE
reject 'Duplicate manifest files: config/example'

fixture claimed-claimed
cat > "$concern/Makefile" <<'MAKEFILE'
claimed_outputs = ${stage}/config/example ${stage}/config/example
include ${PROTOCOL_MK}
${stage}/config/example:
	touch transformed
MAKEFILE
reject 'Duplicate manifest files: config/example'

fixture staged-vendor
printf plain > "$concern/src/config/example"
printf vendored > "$concern/vendor/config/example"
reject 'Duplicate manifest files: config/example'

fixture ancestor
printf file > "$concern/src/config/parent"
mkdir -p "$concern/vendor/config/parent/nested"
printf child > "$concern/vendor/config/parent/nested/child"
reject 'Manifest paths declared as both file and directory: config/parent'

fixture reverse-ancestor
mkdir -p "$concern/src/config/parent/nested"
printf child > "$concern/src/config/parent/nested/child"
printf file > "$concern/vendor/config/parent"
reject 'Manifest paths declared as both file and directory: config/parent'

fixture empty-directory
printf rendered > "$concern/src/config/parent.m4"
mkdir -p "$concern/src/config/parent/empty"
printf private > "$concern/src/config/parent/empty/.keep"
reject 'Manifest paths declared as both file and directory: config/parent'

# Distinct declarations can share directories; private/unmapped vendor files
# do not enter validation. Claimed sources are excluded from ordinary mapping.
fixture valid
mkdir -p "$concern/vendor/build" "$concern/vendor/config/.private"
printf generated > "$concern/src/config/plain"
printf transformed > "$concern/src/config/custom.input"
printf vendored > "$concern/vendor/config/other"
printf ignored > "$concern/vendor/build/plain"
printf ignored > "$concern/vendor/config/.private/plain"
cat > "$concern/Makefile" <<'MAKEFILE'
claimed_sources = ${src}/config/custom.input
claimed_outputs = ${stage}/config/custom.input
include ${PROTOCOL_MK}
${stage}/config/custom.input: ${src}/config/custom.input
	mkdir -p '$(@D)'
	cp '$<' '$@'
MAKEFILE
make --no-print-directory -C "$concern" check-declarations M4= RSYNC=
make --no-print-directory -j4 -C "$concern" install
test -f "$XDG_CONFIG_HOME/plain"
test -f "$XDG_CONFIG_HOME/custom.input"
test -f "$XDG_CONFIG_HOME/other"
test ! -e "$concern/stage/stale"

# Uninstall trusts its receipt even if the current declaration becomes invalid.
printf collision > "$concern/vendor/config/plain"
make --no-print-directory -C "$concern" uninstall
test ! -e "$XDG_CONFIG_HOME/plain"
test ! -e "$XDG_CONFIG_HOME/custom.input"
test ! -e "$XDG_CONFIG_HOME/other"
printf 'declaration validation: PASS\n'
