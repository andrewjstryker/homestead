#!/usr/bin/env bats
# shellcheck source=tests/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup() {
    setup_sandbox
    minimal_module
    mkdir -p "$module/src/libexec/example" "$module/vendor/libexec/example"
    printf '#!/bin/sh\nprintf "helper\\n"\n' > "$module/src/libexec/example/helper"
    chmod +x "$module/src/libexec/example/helper"
    printf '#!/bin/sh\nexit 0\n' > "$module/vendor/libexec/example/vendor-helper"
    chmod +x "$module/vendor/libexec/example/vendor-helper"
    printf 'helper=M4_LIBEXEC_DIR/example/helper\n' > "$module/src/config/caller.m4"
}

@test "libexec defaults and overrides are rendered and invalidate m4 outputs" {
    run env -u LIBEXEC_DIR make --no-print-directory -C "$module" stage
    assert_success
    [ "$(cat "$module/stage/config/caller")" = "helper=$HOME/.local/libexec/example/helper" ]
    make_module stage
    [ "$(cat "$module/stage/config/caller")" = "helper=$LIBEXEC_DIR/example/helper" ]
    run make_module inspect
    assert_success
    assert_output_contains "$LIBEXEC_DIR/example/helper"
    export HOMESTEAD_ROOT=$work MODULES_FIRST='' MODULES_LAST=''
    run "$home" show module
    assert_success
    assert_output_contains "$LIBEXEC_DIR"
}

@test "libexec installs private executables, receipts, and preserves modified files" {
    make_module install
    [ "$(stat -c %a "$LIBEXEC_DIR/example/helper")" = 700 ]
    [ "$(stat -c %a "$LIBEXEC_DIR/example/vendor-helper")" = 700 ]
    [ "$("$LIBEXEC_DIR/example/helper")" = helper ]
    grep -Fq "$LIBEXEC_DIR/example/helper" "$module/.homestead/receipt"
    printf modified > "$LIBEXEC_DIR/example/vendor-helper"
    make_module uninstall
    [ ! -e "$LIBEXEC_DIR/example/helper" ]
    [ "$(cat "$LIBEXEC_DIR/example/vendor-helper")" = modified ]
}

@test "libexec respects preview and DESTDIR without changing rendered paths" {
    run make_module preview
    assert_success
    [ ! -e "$LIBEXEC_DIR" ]
    export DESTDIR=$work/dest
    make_module install
    [ -x "$DESTDIR$LIBEXEC_DIR/example/helper" ]
    [ ! -e "$LIBEXEC_DIR" ]
    [ "$(cat "$DESTDIR$XDG_CONFIG_HOME/caller")" = "helper=$LIBEXEC_DIR/example/helper" ]
    make_module uninstall
    [ ! -e "$DESTDIR$LIBEXEC_DIR/example/helper" ]
}
