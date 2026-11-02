#!/usr/bin/env bats
# shellcheck source=tests/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"
setup() {
    setup_sandbox
    mkdir -p "$module/src/config/empty" "$module/vendor/data/empty"
    printf ignored > "$module/src/config/empty/.keep"
    printf plain > "$module/src/config/plain"
    printf 'M4_VALUE\n' > "$module/src/config/rendered.m4"
    cat > "$module/Build.mk" <<'MAKEFILE'
include ../_homestead/prelude.mk
required_inputs = VALUE
claimed_outputs = stage/config/generated/one stage/config/generated/two
include ../_homestead/homestead.mk

# Target-specific input must remain visible during preflight, even with -f.
check: VALUE = configured

${claimed_outputs}:
	test -d '$(@D)'
	printf generated > '$@'
	printf '%s\n' '$@' >> builds
MAKEFILE
    graph_make() { make_module -j4 -f Build.mk "$@"; }
}

@test "target-specific preflight inputs work with alternate Makefiles without staging" {
    graph_make check
    [ ! -e "$module/stage" ]
    run graph_make stage VALUE=
    assert_failure
    [ ! -e "$module/stage" ]
}

@test "parallel staging creates claimed parents and ignores directory mtime changes" {
    graph_make stage VALUE=first RSYNC=
    [ "$(wc -l < "$module/builds")" -eq 2 ]
    touch "$module/stage/config/generated"
    graph_make stage VALUE=first
    [ "$(wc -l < "$module/builds")" -eq 2 ]
    rm "$module/stage/config/generated/one" "$module/stage/config/generated/two"
    graph_make stage VALUE=first
    [ "$(wc -l < "$module/builds")" -eq 4 ]
}

@test "declared empty directories survive staging and install in both source trees" {
    graph_make stage VALUE=first
    rmdir "$module/stage/config/empty"
    graph_make install VALUE=first
    [ -d "$module/stage/config/empty" ]
    [ -d "$XDG_CONFIG_HOME/empty" ]
    [ -d "$XDG_DATA_HOME/empty" ]
}
