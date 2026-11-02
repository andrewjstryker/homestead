#!/usr/bin/env bats
# shellcheck source=tests/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"
setup() {
    setup_sandbox
    collection=$work/collection
    mkdir -p "$collection"
    collection_homestead "$collection"
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
    drive_vars+=(HOMESTEAD_ROOT MODULES_FIRST MODULES_LAST)
    composed=$collection/zsh/stage/config/composed.conf
}

@test "full staging composes all modules and targeted staging retains their snapshots" {
    drive stage
    [ "$(cat "$composed")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=middle' ]
    printf 'MIDDLE_FRAGMENT=edited\n' > "$collection/middle/src/config/env.d/middle.sh"
    printf 'changed shell\n' > "$collection/zsh/src/config/zsh.conf"
    drive stage zsh
    [ "$(cat "$composed")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=middle' ]
    [ "$(cat "$collection/zsh/stage/config/zsh.conf")" = 'changed shell' ]
    [ "$(wc -l < "$collection/middle/stage-events")" -eq 1 ]
    [ "$(wc -l < "$collection/base/stage-events")" -eq 2 ]
    drive stage middle zsh
    [ "$(cat "$composed")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=edited' ]
}

@test "a clean consumer build stages only foundations and the consumer" {
    drive stage zsh
    [ "$(cat "$composed")" = BASE_FRAGMENT=base ]
    [ -f "$collection/base/stage/config/base.conf" ]
    [ ! -e "$collection/middle/stage" ]
    [ ! -e "$collection/middle/stage-events" ]
}

@test "cleaning a middle stage opts it out of later consumer composition" {
    drive stage
    drive clean middle
    drive stage zsh
    [ "$(cat "$composed")" = BASE_FRAGMENT=base ]
    [ ! -e "$collection/middle/stage" ]
    [ "$(wc -l < "$collection/middle/stage-events")" -eq 1 ]
}

@test "vendor fragments participate only after staging and survive source removal until restaged" {
    mkdir -p "$collection/middle/vendor/config/env.d"
    printf 'VENDOR_FRAGMENT=vendor\n' > "$collection/middle/vendor/config/env.d/vendor.sh"
    drive stage zsh
    [ "$(cat "$composed")" = BASE_FRAGMENT=base ]
    drive stage middle zsh
    [ "$(cat "$composed")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=middle\nVENDOR_FRAGMENT=vendor' ]
    rm "$collection/middle/vendor/config/env.d/vendor.sh"
    drive stage zsh
    [ "$(tail -1 "$composed")" = VENDOR_FRAGMENT=vendor ]
    drive stage middle zsh
    [ "$(cat "$composed")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=middle' ]
}

@test "targeted install and preview retain contributors without installing foundations or middle modules" {
    drive stage
    drive preview zsh
    [ ! -e "$XDG_CONFIG_HOME" ]
    drive install zsh
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
    drive install zsh
    [ "$(cat "$XDG_CONFIG_HOME/composed.conf")" = BASE_FRAGMENT=base ]
    run drive BASE_STAGE_TOOL= install zsh
    assert_failure
    assert_output_contains 'FAILED (check-stage-tools): base'
}

@test "failed selected producers cannot contribute stale staged fragments" {
    drive stage
    cat >> "$collection/middle/Makefile" <<'MAKEFILE'
stage_tools += MISSING_TOOL
MISSING_TOOL :=
MAKEFILE
    run drive stage middle zsh
    assert_failure
    [ "$(cat "$composed")" = BASE_FRAGMENT=base ]
}

@test "composition follows configured stage roots rather than source declarations" {
    # Move an existing snapshot and change its declared root. Do not rebuild it.
    drive stage
    mv "$collection/middle/stage" "$collection/middle/assembled"
    sed -i '1istage := assembled' "$collection/middle/Makefile"
    rm "$collection/middle/src/config/env.d/middle.sh"
    drive stage zsh
    [ "$(cat "$composed")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=middle' ]
    [ "$(wc -l < "$collection/middle/stage-events")" -eq 1 ]
}

@test "fragment paths preserve spaces in the collection root" {
    mv "$collection" "$work/collection with spaces"
    collection=$work/'collection with spaces'
    export HOMESTEAD_ROOT=$collection
    drive_vars+=(HOMESTEAD_ROOT)
    drive stage
    drive stage zsh
    [ "$(cat "$collection/zsh/stage/config/composed.conf")" = $'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=middle' ]
}
