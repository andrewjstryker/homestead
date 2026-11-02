#!/usr/bin/env bats
# shellcheck source=tests/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"
setup() {
    setup_sandbox
    collection=$work/collection
    mkdir -p "$collection"
    collection_homestead "$collection"
    cp -R "$BATS_TEST_DIRNAME/driver-fixture/." "$collection/"
    export HOMESTEAD_ROOT=$collection MODULES_FIRST=base MODULES_LAST=zsh
    export SYNC_LOG=$work/sync.log
    drive_vars+=(HOMESTEAD_ROOT MODULES_FIRST MODULES_LAST SYNC_LOG)
}

@test "selection follows configurable first and last module policy" {
    run drive show zsh middle base
    assert_success
    headings=$(printf '%s\n' "$output" | sed -n 's/^==> \([^:]*\): show$/\1/p')
    [ "$headings" = $'base\nmiddle\nzsh' ]
    run drive MODULES_FIRST=middle MODULES_LAST=base show zsh middle base
    assert_success
    headings=$(printf '%s\n' "$output" | sed -n 's/^==> \([^:]*\): show$/\1/p')
    [ "$headings" = $'middle\nzsh\nbase' ]
    run drive MODULES_FIRST='' MODULES_LAST='' show zsh base middle
    assert_success
    headings=$(printf '%s\n' "$output" | sed -n 's/^==> \([^:]*\): show$/\1/p')
    [ "$headings" = $'zsh\nbase\nmiddle' ]
}

@test "apply installs all modules before sync and composes ordered fragments" {
    # The consumer's sync recipe checks that every selected module is installed.
    run drive EXPECT_MIDDLE=1 apply base middle zsh
    assert_success
    [ "$(cat "$SYNC_LOG")" = sync ]
    [ "$(cat "$collection/zsh/stage/config/composed.conf")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=middle' ]
}

@test "DESTDIR apply prefixes writes and skips live sync" {
    run drive apply --destdir "$work/destdir" base middle zsh
    assert_success
    for name in base middle zsh; do
        [ -f "$work/destdir$XDG_CONFIG_HOME/$name.conf" ]
    done
    [ ! -e "$XDG_CONFIG_HOME" ]
    [ ! -e "$SYNC_LOG" ]
}

@test "check rejects shared destinations across modules" {
    run drive check collision-a collision-b
    assert_failure
    assert_output_contains 'destination collision:'
    assert_output_contains shared.sh
}

@test "check aggregates independent module failures" {
    run drive check fail-a fail-b
    assert_failure
    assert_output_contains 'FAILED (check): fail-a fail-b'
}

@test "implicit check reports selected module failures" {
    run drive check
    assert_failure
    assert_output_contains 'FAILED (check): fail-a fail-b'
}

@test "optional module test targets run, skip, and propagate failure" {
    run drive test
    assert_success
    assert_output_contains '==> middle: test'
    assert_output_contains 'test (skipped: no test target)'
    run drive FAIL_TEST=1 test middle
    assert_failure
    assert_output_contains 'FAILED (test): middle'
}

@test "private and infrastructure directories cannot be selected" {
    mkdir -p "$collection/_infrastructure" "$collection/.private"
    printf '$(error infrastructure must never be parsed)\n' > "$collection/_infrastructure/Makefile"
    cp "$collection/_infrastructure/Makefile" "$collection/.private/Makefile"
    run drive show
    assert_success
    for private in _homestead _infrastructure .private; do
        run drive show "$private"
        assert_failure
        assert_output_contains 'no such module'
    done
}

@test "root selection supports spaces, symlink modules, and explicit precedence" {
    other=$work/'other collection'
    mkdir -p "$other"
    ln -s "$collection/middle" "$other/linked"
    # drive passes the setup collection first; the later --root wins.
    run drive --root "$other" show linked
    assert_success
    assert_output_contains '==> linked: show'
    # An inherited HOMESTEAD_ROOT is not a root; the default is the caller's directory.
    cd "$other"
    run env HOMESTEAD_ROOT=/nonexistent "$home" --env "$work/drive.env" show linked
    assert_success
    assert_output_contains '==> linked: show'
}

@test "collision checks compare resolved destination roots" {
    printf '\nXDG_CONFIG_HOME := ${XDG_CONFIG_HOME}/separate\n' >> "$collection/collision-b/Makefile"
    run drive check collision-a collision-b
    assert_success
}

@test "compatibility links conflict with descendant destinations" {
    mkdir -p "$collection/linker/src/config" "$collection/descendant/src/config/node"
    printf link > "$collection/linker/src/config/item"
    printf child > "$collection/descendant/src/config/node/child"
    cat > "$collection/linker/Makefile" <<'MAKEFILE'
include ../_homestead/prelude.mk
links := config/item
include ../_homestead/homestead.mk
link_of = ${XDG_CONFIG_HOME}/node
MAKEFILE
    printf 'include ../_homestead/prelude.mk\ninclude ../_homestead/homestead.mk\n' > "$collection/descendant/Makefile"
    run drive check linker descendant
    assert_failure
    assert_output_contains 'destination collision:'
    assert_output_contains /node
    run drive check base middle
    assert_success
}

@test "driver uninstall does not stage or inspect modules" {
    drive install middle
    cat >> "$collection/middle/Makefile" <<'MAKEFILE'
.PHONY: forbidden-build
forbidden-build:
	false
check-stage-tools inspect: forbidden-build
MAKEFILE
    run drive uninstall middle
    assert_success
    [ ! -e "$XDG_CONFIG_HOME/middle.conf" ]
}

@test "collection check remains read-only and reports all preflight failures" {
    # A collection with only valid modules exercises implicit discovery.
    for name in collision-a collision-b fail-a fail-b unavailable runtime-fail; do
        rm -rf "${collection:?}/$name"
    done
    run drive check
    assert_success
    run drive RSYNC= check
    assert_failure
    assert_output_contains 'FAILED (check): base middle zsh'
    run drive REQUIRED_TOOL= check
    assert_failure
    assert_output_contains 'FAILED (check): middle'
    for name in base middle zsh; do
        [ ! -e "$collection/$name/stage" ]
        [ ! -e "$collection/$name/.homestead" ]
    done
}

@test "install preflights installation tools across the selection before any writes" {
    run drive REQUIRED_TOOL= install base middle zsh
    assert_failure
    assert_output_contains 'FAILED (check-install-tools): middle'
    [ ! -e "$XDG_CONFIG_HOME" ]
    [ ! -e "$collection/base/.homestead" ]
}

@test "install preflights the last consumer before installing earlier modules" {
    run drive ZSH_TOOL= install base middle zsh
    assert_failure
    assert_output_contains 'FAILED (check-stage-tools): zsh'
    [ ! -e "$XDG_CONFIG_HOME" ]
    [ ! -e "$collection/base/.homestead" ]
}

@test "install command tail preserves arguments and inherits resolved environment" {
    mkdir -p "$collection/base/src/bin"
    cat > "$collection/base/src/bin/after-install" <<'SCRIPT'
#!/bin/sh
[ -f "$XDG_CONFIG_HOME/base.conf" ] || exit 90
mkdir -p "$XDG_STATE_HOME"
printf '%s\n' "$TOOLCHAINS" "$@" > "$XDG_STATE_HOME/command-result"
SCRIPT
    chmod +x "$collection/base/src/bin/after-install"
    run drive 'TOOLCHAINS=rust go' install base -- after-install 'argument with spaces' '$(false)' --flag
    assert_success
    [ "$(cat "$XDG_STATE_HOME/command-result")" = $'rust go\nargument with spaces\n$(false)\n--flag' ]
    run drive TOOLCHAINS= install base -- after-install override
    assert_success
    [ "$(cat "$XDG_STATE_HOME/command-result")" = $'\noverride' ]
}

@test "inherited environment never becomes a module input" {
    # An installed env.d fragment exports values such as the XDG roots into
    # every shell. Read back, a stale export would beat the table and defaults.
    mkdir -p "$collection/base/src/bin"
    cat > "$collection/base/src/bin/report" <<'SCRIPT'
#!/bin/sh
mkdir -p "$XDG_STATE_HOME"
printf '%s|%s|%s\n' "${TOOLCHAINS-unset}" "${STALE_EXPORT-unset}" "$XDG_STATE_HOME" > "$XDG_STATE_HOME/report"
SCRIPT
    chmod +x "$collection/base/src/bin/report"
    drive TOOLCHAINS=from-table show base > /dev/null
    run env STALE_EXPORT=inherited TOOLCHAINS=inherited XDG_STATE_HOME=/inherited \
        MODULES_FIRST=inherited ENV_FILE=/inherited \
        "$home" --root "$collection" --env "$work/drive.env" install base -- report
    assert_success
    [ "$(cat "$XDG_STATE_HOME/report")" = "from-table|unset|$XDG_STATE_HOME" ]
}

@test "--first and --last replace the table's ordering, the last option winning" {
    run drive MODULES_LAST=base show --last middle --last zsh
    assert_success
    assert_output_contains 'MODULES_LAST....... zsh'
    run drive --first '' --last= show zsh base middle
    assert_success
    headings=$(printf '%s\n' "$output" | sed -n 's/^==> \([^:]*\): show$/\1/p')
    [ "$headings" = $'zsh\nbase\nmiddle' ]
    run drive show --first
    assert_failure
    assert_output_contains 'requires a module list'
}

@test "the driver rejects a missing or malformed table before any module runs" {
    run drive --env "$work/absent.env" show
    assert_failure
    assert_output_contains 'no such env file'
    printf 'EMAIL = "someone@example.com"\nPATH=/elsewhere\n' > "$work/bad.env"
    run "$home" --root "$collection" --env "$work/bad.env" show
    assert_failure
    assert_output_contains 'bad.env:1: expected NAME=value'
    assert_output_contains 'bad.env:2: PATH: not a table input'
    [[ "$output" != *'==> '* ]]
}

@test "the collection table is optional and modules never fall back to their own" {
    printf 'BASE_TOOL=\n' > "$collection/base/.env"
    run "$home" --root "$collection" check base
    assert_success
    run "$home" --root "$collection" show base
    assert_success
    assert_output_contains 'ENV_FILE........... (none)'
    assert_output_contains "HOME............... $HOME"
    printf 'BASE_TOOL=\n' > "$collection/.env"
    run "$home" --root "$collection" check base
    assert_failure
    assert_output_contains 'Missing tools needed to stage: BASE_TOOL'
}

@test "install command tail cannot run before success or during dry-run and staging" {
    run drive RSYNC= install base -- touch "$work/executed"
    assert_failure
    [ ! -e "$work/executed" ]
    run drive install base --dry-run -- touch "$work/executed"
    assert_success
    assert_output_contains 'Would run after install:'
    [ ! -e "$work/executed" ]
    run drive install base --destdir "$work/dest" -- touch "$work/executed"
    assert_failure
    [ ! -e "$work/executed" ]
    [ ! -e "$work/dest" ]
    run drive stage base -- touch "$work/executed"
    assert_failure
    run drive install base --
    assert_failure
}

@test "install command tail propagates the command exit status" {
    run drive install base -- sh -c 'exit 17'
    [ "$status" -eq 17 ]
}
