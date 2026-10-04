#!/usr/bin/env bats
# shellcheck source=tests/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"
setup() { setup_sandbox; }

@test "full preflight aggregates independent failures without mutating state" {
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

    run make_module -j4 check REQUIRED_VALUE= M4= RSYNC= MD5SUM= SYNC_TOOL=
    assert_failure
    for message in \
        'Duplicate manifest files: config/example' \
        'Missing required inputs needed to stage: REQUIRED_VALUE' \
        'Missing tools needed to stage: M4' \
        'Missing tools needed to install: RSYNC' \
        'Missing tools needed to uninstall: MD5SUM' \
        'Missing tools needed to sync: SYNC_TOOL'; do
        assert_output_contains "$message"
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

}

@test "phase gates require their own tools and run before parallel staging mutations" {
    fixture_module
    mkdir -p "$module/stage/config"
    printf stale > "$module/stage/config/stale"
    for missing in M4 STAGE_TOOL TRANSFORM_TOOL CONTEXT_INPUT; do
        run make_module -j4 stage "$missing="
        assert_failure
        assert_output_contains "$missing"
        [ "$(cat "$module/stage/config/stale")" = stale ]
    done
    make_module stage INSTALL_TOOL= SYNC_TOOL=
    make_module sync STAGE_TOOL= INSTALL_TOOL=
    for missing in RSYNC INSTALL_TOOL; do
        run make_module install "$missing="
        assert_failure
        assert_output_contains "Missing tools needed to install: $missing"
        [ ! -e "$XDG_CONFIG_HOME" ]
    done
    run make_module sync SYNC_TOOL=
    assert_failure
    assert_output_contains 'Missing tools needed to sync: SYNC_TOOL'
    make_module install SYNC_TOOL=
}

@test "missing render inputs leave diagnostics and cleanup available" {
    fixture_module
    make_module help CONTEXT_INPUT=
    run make_module show CONTEXT_INPUT=
    assert_success
    assert_output_contains '(MISSING)'
    make_module clean CONTEXT_INPUT=
}

@test "explicitly empty installation roots are rejected by Make and the driver" {
    fixture_module
    export HOMESTEAD_ROOT=$work MODULES_FIRST='' MODULES_LAST=''
    for variable in XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME BIN_DIR; do
        run make_module show "$variable="
        assert_failure
        assert_output_contains "$variable must not be empty"
        run env "$variable=" "$home" show module
        assert_failure
        assert_output_contains "$variable must not be empty"
    done
}
