#!/usr/bin/env bats
# shellcheck source=tests/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"
setup() {
    setup_sandbox
    collection=$work/collection
    mkdir -p "$collection"
    cp -R "$BATS_TEST_DIRNAME/driver-fixture/." "$collection/"
    export HOMESTEAD_ROOT=$collection MODULES_FIRST=base MODULES_LAST=zsh
    export SYNC_LOG=$work/sync.log
}

@test "selection follows configurable first and last module policy" {
    run "$home" show zsh middle base
    assert_success
    headings=$(printf '%s\n' "$output" | sed -n 's/^==> \([^:]*\): show$/\1/p')
    [ "$headings" = $'base\nmiddle\nzsh' ]
    run env MODULES_FIRST=middle MODULES_LAST=base "$home" show zsh middle base
    assert_success
    headings=$(printf '%s\n' "$output" | sed -n 's/^==> \([^:]*\): show$/\1/p')
    [ "$headings" = $'middle\nzsh\nbase' ]
    run env MODULES_FIRST='' MODULES_LAST='' "$home" show zsh base middle
    assert_success
    headings=$(printf '%s\n' "$output" | sed -n 's/^==> \([^:]*\): show$/\1/p')
    [ "$headings" = $'zsh\nbase\nmiddle' ]
}

@test "apply installs all modules before sync and composes ordered fragments" {
    # The consumer's sync recipe checks that every selected module is installed.
    run env EXPECT_MIDDLE=1 "$home" apply base middle zsh
    assert_success
    [ "$(cat "$SYNC_LOG")" = sync ]
    [ "$(cat "$collection/zsh/stage/config/composed.conf")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=middle' ]
}

@test "DESTDIR apply prefixes writes and skips live sync" {
    run "$home" apply --destdir "$work/destdir" base middle zsh
    assert_success
    for name in base middle zsh; do
        [ -f "$work/destdir$XDG_CONFIG_HOME/$name.conf" ]
    done
    [ ! -e "$XDG_CONFIG_HOME" ]
    [ ! -e "$SYNC_LOG" ]
}

@test "check rejects shared destinations across modules" {
    run "$home" check collision-a collision-b
    assert_failure
    assert_output_contains 'destination collision:'
    assert_output_contains shared.sh
}

@test "check aggregates independent module failures" {
    run "$home" check fail-a fail-b
    assert_failure
    assert_output_contains 'FAILED (check): fail-a fail-b'
}

@test "implicit check reports selected module failures" {
    run "$home" check
    assert_failure
    assert_output_contains 'FAILED (check): fail-a fail-b'
}

@test "optional module test targets run, skip, and propagate failure" {
    run "$home" test
    assert_success
    assert_output_contains '==> middle: test'
    assert_output_contains 'test (skipped: no test target)'
    run env FAIL_TEST=1 "$home" test middle
    assert_failure
    assert_output_contains 'FAILED (test): middle'
}

@test "private and infrastructure directories cannot be selected" {
    mkdir -p "$collection/_homestead" "$collection/.private"
    printf '$(error infrastructure must never be parsed)\n' > "$collection/_homestead/Makefile"
    cp "$collection/_homestead/Makefile" "$collection/.private/Makefile"
    run "$home" show
    assert_success
    for private in _homestead .private; do
        run "$home" show "$private"
        assert_failure
        assert_output_contains 'no such module'
    done
}

@test "root selection supports spaces, symlink modules, and explicit precedence" {
    other=$work/'other collection'
    mkdir -p "$other"
    ln -s "$collection/middle" "$other/linked"
    run env HOMESTEAD_ROOT=/nonexistent "$home" --root "$other" show linked
    assert_success
    assert_output_contains '==> linked: show'
    cd "$other"
    unset HOMESTEAD_ROOT
    run "$home" show linked
    assert_success
    assert_output_contains '==> linked: show'
}

@test "collision checks compare resolved destination roots" {
    printf '\nXDG_CONFIG_HOME := ${XDG_CONFIG_HOME}/separate\n' >> "$collection/collision-b/Makefile"
    run "$home" check collision-a collision-b
    assert_success
}

@test "compatibility links conflict with descendant destinations" {
    mkdir -p "$collection/linker/src/config" "$collection/descendant/src/config/node"
    printf link > "$collection/linker/src/config/item"
    printf child > "$collection/descendant/src/config/node/child"
    cat > "$collection/linker/Makefile" <<'MAKEFILE'
links := config/item
include ${HOMESTEAD_MK}
link_of = ${XDG_CONFIG_HOME}/node
MAKEFILE
    printf 'include ${HOMESTEAD_MK}\n' > "$collection/descendant/Makefile"
    run "$home" check linker descendant
    assert_failure
    assert_output_contains 'destination collision:'
    assert_output_contains /node
    run "$home" check base middle
    assert_success
}

@test "driver uninstall does not stage or inspect modules" {
    "$home" install middle
    cat >> "$collection/middle/Makefile" <<'MAKEFILE'
.PHONY: forbidden-build
forbidden-build:
	false
check-stage-tools inspect: forbidden-build
MAKEFILE
    run "$home" uninstall middle
    assert_success
    [ ! -e "$XDG_CONFIG_HOME/middle.conf" ]
}

@test "collection check remains read-only and reports all preflight failures" {
    # A collection with only valid modules exercises implicit discovery.
    for name in collision-a collision-b fail-a fail-b unavailable runtime-fail; do
        rm -rf "${collection:?}/$name"
    done
    run "$home" check
    assert_success
    run env RSYNC= "$home" check
    assert_failure
    assert_output_contains 'FAILED (check): base middle zsh'
    run env REQUIRED_TOOL= "$home" check
    assert_failure
    assert_output_contains 'FAILED (check): middle'
    for name in base middle zsh; do
        [ ! -e "$collection/$name/stage" ]
        [ ! -e "$collection/$name/.homestead" ]
    done
}

@test "install preflights installation tools across the selection before any writes" {
    run env REQUIRED_TOOL= "$home" install base middle zsh
    assert_failure
    assert_output_contains 'FAILED (check-install-tools): middle'
    [ ! -e "$XDG_CONFIG_HOME" ]
    [ ! -e "$collection/base/.homestead" ]
}

@test "install preflights the last consumer before installing earlier modules" {
    run env ZSH_TOOL= "$home" install base middle zsh
    assert_failure
    assert_output_contains 'FAILED (check-stage-tools): zsh'
    [ ! -e "$XDG_CONFIG_HOME" ]
    [ ! -e "$collection/base/.homestead" ]
}
