#!/usr/bin/env bats
# shellcheck source=tests/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"
setup() {
    setup_sandbox
    collection=$work/collection
    mkdir -p "$collection"
    for name in base middle zsh; do
        cp -R "$BATS_TEST_DIRNAME/driver-fixture/$name" "$collection/$name"
        cat >> "$collection/$name/Makefile" <<'MAKEFILE'
.PHONY: observe-stage
observe-stage:
	printf '%s\n' '$(notdir ${CURDIR})' >> stage-events
stage: observe-stage
MAKEFILE
    done
    export HOMESTEAD_ROOT=$collection MODULES_FIRST=base MODULES_LAST=zsh
    composed=$collection/zsh/stage/config/composed.conf
}

@test "full staging composes all modules and targeted staging retains their snapshots" {
    "$home" stage
    [ "$(cat "$composed")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=middle' ]
    printf 'MIDDLE_FRAGMENT=edited\n' > "$collection/middle/src/config/env.d/middle.sh"
    printf 'changed shell\n' > "$collection/zsh/src/config/zsh.conf"
    "$home" stage zsh
    [ "$(cat "$composed")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=middle' ]
    [ "$(cat "$collection/zsh/stage/config/zsh.conf")" = 'changed shell' ]
    [ "$(wc -l < "$collection/middle/stage-events")" -eq 1 ]
    [ "$(wc -l < "$collection/base/stage-events")" -eq 2 ]
    "$home" stage middle zsh
    [ "$(cat "$composed")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=edited' ]
}

@test "a clean consumer build stages only foundations and the consumer" {
    "$home" stage zsh
    [ "$(cat "$composed")" = BASE_FRAGMENT=base ]
    [ -f "$collection/base/stage/config/base.conf" ]
    [ ! -e "$collection/middle/stage" ]
    [ ! -e "$collection/middle/stage-events" ]
}

@test "cleaning a middle stage opts it out of later consumer composition" {
    "$home" stage
    "$home" clean middle
    "$home" stage zsh
    [ "$(cat "$composed")" = BASE_FRAGMENT=base ]
    [ ! -e "$collection/middle/stage" ]
    [ "$(wc -l < "$collection/middle/stage-events")" -eq 1 ]
}

@test "vendor fragments participate only after staging and survive source removal until restaged" {
    mkdir -p "$collection/middle/vendor/config/env.d"
    printf 'VENDOR_FRAGMENT=vendor\n' > "$collection/middle/vendor/config/env.d/vendor.sh"
    "$home" stage zsh
    [ "$(cat "$composed")" = BASE_FRAGMENT=base ]
    "$home" stage middle zsh
    [ "$(cat "$composed")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=middle\nVENDOR_FRAGMENT=vendor' ]
    rm "$collection/middle/vendor/config/env.d/vendor.sh"
    "$home" stage zsh
    [ "$(tail -1 "$composed")" = VENDOR_FRAGMENT=vendor ]
    "$home" stage middle zsh
    [ "$(cat "$composed")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=middle' ]
}

@test "targeted install and preview retain contributors without installing foundations or middle modules" {
    "$home" stage
    "$home" preview zsh
    [ ! -e "$XDG_CONFIG_HOME" ]
    "$home" install zsh
    [ "$(cat "$XDG_CONFIG_HOME/composed.conf")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=middle' ]
    [ ! -e "$XDG_CONFIG_HOME/base.conf" ]
    [ ! -e "$XDG_CONFIG_HOME/middle.conf" ]
    [ ! -e "$collection/base/.homestead" ]
    [ ! -e "$collection/middle/.homestead" ]
    [ "$(wc -l < "$collection/middle/stage-events")" -eq 1 ]
}

@test "implicit foundations require staging tools but not installation tools" {
    cat >> "$collection/base/Makefile" <<'MAKEFILE'
stage_tools += BASE_STAGE_TOOL
install_tools += BASE_INSTALL_TOOL
BASE_STAGE_TOOL ?= /bin/true
BASE_INSTALL_TOOL :=
MAKEFILE
    "$home" install zsh
    [ "$(cat "$XDG_CONFIG_HOME/composed.conf")" = BASE_FRAGMENT=base ]
    run env BASE_STAGE_TOOL= "$home" install zsh
    assert_failure
    assert_output_contains 'FAILED (check-stage-tools): base'
}

@test "failed selected producers cannot contribute stale staged fragments" {
    "$home" stage
    cat >> "$collection/middle/Makefile" <<'MAKEFILE'
stage_tools += MISSING_TOOL
MISSING_TOOL :=
MAKEFILE
    run "$home" stage middle zsh
    assert_failure
    [ "$(cat "$composed")" = BASE_FRAGMENT=base ]
}

@test "composition follows configured stage roots rather than source declarations" {
    # Move an existing snapshot and change its declared root. Do not rebuild it.
    "$home" stage
    mv "$collection/middle/stage" "$collection/middle/assembled"
    sed -i '1istage := assembled' "$collection/middle/Makefile"
    rm "$collection/middle/src/config/env.d/middle.sh"
    "$home" stage zsh
    [ "$(cat "$composed")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=middle' ]
    [ "$(wc -l < "$collection/middle/stage-events")" -eq 1 ]
}

@test "fragment paths preserve spaces in the collection root" {
    mv "$collection" "$work/collection with spaces"
    collection=$work/'collection with spaces'
    export HOMESTEAD_ROOT=$collection
    "$home" stage
    "$home" stage zsh
    [ "$(cat "$collection/zsh/stage/config/composed.conf")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=middle' ]
}
