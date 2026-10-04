#!/usr/bin/env bats
# shellcheck source=tests/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"
setup() {
    setup_sandbox
    export HOMESTEAD_ROOT=$work
    export MODULES_FIRST=floor MODULES_LAST=$'shell\nother-shell'
    export EVENTS=$work/events
    for module in floor middle other shell other-shell; do
        mkdir -p "$work/$module/src/config/env.d"
        printf '%s\n' "$module" >"$work/$module/src/config/env.d/$module.sh"
        cat >"$work/$module/Makefile" <<'MAKEFILE'
module := $(notdir ${CURDIR})
stage_tools += FIXTURE_TOOL
FIXTURE_TOOL = $(if $(filter ${module},${FAIL_PREFLIGHT}),,/bin/true)
include ${HOMESTEAD_MK}
.PHONY: observe-stage observe-install observe-sync observe-inspect
observe-stage: check-stage-tools
	printf 'stage %s\n' '${module}' >> "$${EVENTS}"
	printf '%s\n' "$${ENV_FRAGMENTS-}" > received-fragments
	$(if $(filter ${module},${FAIL_STAGE}),false,:)
stage: observe-stage
observe-install: stage check-install-tools
	printf 'install %s\n' '${module}' >> "$${EVENTS}"
	$(if $(filter ${module},${FAIL_INSTALL}),false,:)
install: observe-install
observe-sync: check-sync-tools
	printf 'sync %s\n' '${module}' >> "$${EVENTS}"
sync: observe-sync
observe-inspect:
	printf 'inspect %s\n' '${module}' >> "$${EVENTS}"
	$(if $(filter ${module},${FAIL_INSPECT}),false,:)
inspect: observe-inspect
MAKEFILE
    done

}

# Keep matrix cases separately selectable while sharing their behavioral oracle.
assert_stage_failure() {
    local variable=$1 phase=$2 selection=$3
    local -a modules=()
    [ "$selection" != explicit ] || modules=(floor middle other shell other-shell)
    export "$variable=floor middle"
    run "$home" stage "${modules[@]}"
    assert_failure
    assert_output_contains "FAILED ($phase): floor middle"
    [ "$(grep -c '^stage other$' "$EVENTS")" -eq 1 ]
    [ "$(grep -c '^stage other-shell$' "$EVENTS")" -eq 1 ]
    run grep -E '/(floor|middle)/' "$work/other-shell/received-fragments"
    [ "$status" -eq 1 ]
    grep -q '/other/stage/config/env.d/other.sh' "$work/other-shell/received-fragments"
}

assert_install_failure() {
    local verb=$1 variable=$2 phase=$3 selection=$4
    local -a modules=()
    [ "$selection" != explicit ] || modules=(floor middle other shell other-shell)
    export "$variable=middle other"
    : > "$EVENTS"
    run "$home" "$verb" "${modules[@]}"
    assert_failure
    assert_output_contains "FAILED ($phase): middle"
    [[ "$output" != *"FAILED ($phase): other"* ]]
    run grep -E '^(install|sync) ' "$EVENTS"
    [ "$status" -eq 1 ]
    if [ "$phase" != check-stage-tools ]; then
        run grep -x "$phase other" "$EVENTS"
        [ "$status" -eq 1 ]
    fi
}

@test "stage aggregates preflight failures and excludes failed producers (implicit)" {
    assert_stage_failure FAIL_PREFLIGHT check-stage-tools implicit
}

@test "install stops on preflight failure before installing (implicit)" {
    assert_install_failure install FAIL_PREFLIGHT check-stage-tools implicit
}

@test "apply stops on preflight failure before installing (implicit)" {
    assert_install_failure apply FAIL_PREFLIGHT check-stage-tools implicit
}

@test "stage aggregates stage failures and excludes failed producers (implicit)" {
    assert_stage_failure FAIL_STAGE stage implicit
}

@test "install stops on stage failure before installing (implicit)" {
    assert_install_failure install FAIL_STAGE stage implicit
}

@test "apply stops on stage failure before installing (implicit)" {
    assert_install_failure apply FAIL_STAGE stage implicit
}

@test "stage aggregates inspect failures and excludes failed producers (implicit)" {
    assert_stage_failure FAIL_INSPECT inspect implicit
}

@test "install stops on inspect failure before installing (implicit)" {
    assert_install_failure install FAIL_INSPECT inspect implicit
}

@test "apply stops on inspect failure before installing (implicit)" {
    assert_install_failure apply FAIL_INSPECT inspect implicit
}

@test "stage aggregates preflight failures and excludes failed producers (explicit)" {
    assert_stage_failure FAIL_PREFLIGHT check-stage-tools explicit
}

@test "install stops on preflight failure before installing (explicit)" {
    assert_install_failure install FAIL_PREFLIGHT check-stage-tools explicit
}

@test "apply stops on preflight failure before installing (explicit)" {
    assert_install_failure apply FAIL_PREFLIGHT check-stage-tools explicit
}

@test "stage aggregates stage failures and excludes failed producers (explicit)" {
    assert_stage_failure FAIL_STAGE stage explicit
}

@test "install stops on stage failure before installing (explicit)" {
    assert_install_failure install FAIL_STAGE stage explicit
}

@test "apply stops on stage failure before installing (explicit)" {
    assert_install_failure apply FAIL_STAGE stage explicit
}

@test "stage aggregates inspect failures and excludes failed producers (explicit)" {
    assert_stage_failure FAIL_INSPECT inspect explicit
}

@test "install stops on inspect failure before installing (explicit)" {
    assert_install_failure install FAIL_INSPECT inspect explicit
}

@test "apply stops on inspect failure before installing (explicit)" {
    assert_install_failure apply FAIL_INSPECT inspect explicit
}

@test "stage continues after failures without a fragment consumer" {
    : > "$EVENTS"
    run env FAIL_STAGE=middle "$home" stage middle other
    assert_failure
    grep -qx 'stage other' "$EVENTS"
    run grep '^inspect ' "$EVENTS"
    [ "$status" -eq 1 ]
}

@test "install stops after staging failures without a fragment consumer" {
    : > "$EVENTS"
    run env FAIL_STAGE=middle "$home" install middle other
    assert_failure
    assert_output_contains 'FAILED (install): middle'
    run grep -x 'stage other' "$EVENTS"
    [ "$status" -eq 1 ]
}

assert_runtime_install_failure() {
    local verb=$1
    shift
    : > "$EVENTS"
    run env FAIL_INSTALL=middle "$home" "$verb" floor middle other shell "$@"
    assert_failure
    assert_output_contains 'FAILED (install): middle'
    grep -qx 'install floor' "$EVENTS"
    run grep -E '^(install other|install shell|sync )' "$EVENTS"
    [ "$status" -eq 1 ]
}

@test "apply stops installation and skips sync after failure in dry-run mode" {
    assert_runtime_install_failure apply --dry-run
    [ ! -e "$XDG_CONFIG_HOME" ]
}

@test "apply stops installation and skips sync after failure in destdir mode" {
    assert_runtime_install_failure apply --destdir "$work/staged"
    [ -s "$work/staged$work/floor/.homestead/receipt" ]
    [ -f "$work/staged$XDG_CONFIG_HOME/env.d/floor.sh" ]
    [ ! -e "$work/staged$XDG_CONFIG_HOME/env.d/other.sh" ]
}

@test "successful producers stage once and consumers receive the same fragments" {
    run "$home" stage
    assert_success
    [ "$(grep -c '^stage ' "$EVENTS")" -eq 5 ]
    cmp "$work/shell/received-fragments" "$work/other-shell/received-fragments"
}

@test "install stops after a runtime failure and keeps earlier successful receipts" {
    assert_runtime_install_failure install
    [ -s "$work/floor/.homestead/receipt" ]
    [ -f "$XDG_CONFIG_HOME/env.d/floor.sh" ]
    [ ! -e "$XDG_CONFIG_HOME/env.d/other.sh" ]
}

@test "apply skips live sync after a runtime installation failure" {
    assert_runtime_install_failure apply
    [ -s "$work/floor/.homestead/receipt" ]
    [ -f "$XDG_CONFIG_HOME/env.d/floor.sh" ]
    [ ! -e "$XDG_CONFIG_HOME/env.d/other.sh" ]
}
