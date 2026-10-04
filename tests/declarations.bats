#!/usr/bin/env bats
# shellcheck source=tests/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"
setup() { setup_sandbox; }

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
        run make_module -j4 "$target"
        assert_failure
        assert_output_contains "$expected"
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


@test "declarations reject plain-template before lifecycle mutation" {
    fixture plain-template
    printf plain > "$module/src/config/example"
    printf rendered > "$module/src/config/example.m4"
    reject 'Duplicate manifest files: config/example'
}

@test "declarations reject claimed-ordinary before lifecycle mutation" {
    fixture claimed-ordinary
    printf plain > "$module/src/config/example"
    cat > "$module/Makefile" <<'MAKEFILE'
claimed_outputs = ${stage}/config/example
include ${HOMESTEAD_MK}
${stage}/config/example:
	touch transformed
MAKEFILE
    reject 'Duplicate manifest files: config/example'
}

@test "declarations reject claimed-claimed before lifecycle mutation" {
    fixture claimed-claimed
    cat > "$module/Makefile" <<'MAKEFILE'
claimed_outputs = ${stage}/config/example ${stage}/config/example
include ${HOMESTEAD_MK}
${stage}/config/example:
	touch transformed
MAKEFILE
    reject 'Duplicate manifest files: config/example'
}

@test "declarations reject staged-vendor before lifecycle mutation" {
    fixture staged-vendor
    printf plain > "$module/src/config/example"
    printf vendored > "$module/vendor/config/example"
    reject 'Duplicate manifest files: config/example'
}

@test "declarations reject ancestor before lifecycle mutation" {
    fixture ancestor
    printf file > "$module/src/config/parent"
    mkdir -p "$module/vendor/config/parent/nested"
    printf child > "$module/vendor/config/parent/nested/child"
    reject 'Manifest paths declared as both file and directory: config/parent'
}

@test "declarations reject reverse-ancestor before lifecycle mutation" {
    fixture reverse-ancestor
    mkdir -p "$module/src/config/parent/nested"
    printf child > "$module/src/config/parent/nested/child"
    printf file > "$module/vendor/config/parent"
    reject 'Manifest paths declared as both file and directory: config/parent'
}

@test "declarations reject empty-directory before lifecycle mutation" {
    fixture empty-directory
    printf rendered > "$module/src/config/parent.m4"
    mkdir -p "$module/src/config/parent/empty"
    printf private > "$module/src/config/parent/empty/.keep"
    reject 'Manifest paths declared as both file and directory: config/parent'
}

@test "valid shared directories and claimed sources install; later conflicts do not block receipt removal" {
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
}
