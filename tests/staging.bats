#!/usr/bin/env bats
# shellcheck source=tests/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"
setup() {
    setup_sandbox
    fixture_module
}

@test "staging maps ordinary, template, and claimed sources without staging vendor files" {
    run make_module -j4 stage
    assert_success
    [ "$(cat "$module/stage/config/static.conf")" = static ]
    [ "$(cat "$module/stage/config/claimed")" = 'CLAIMED TRANSFORMATION' ]
    [ ! -e "$module/stage/config/claimed.upper" ]
    [ "$(cat "$module/stage/config/rendered.conf")" = rendered ]
    [ "$(cat "$module/stage/config/runtime-name.conf")" = 'XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-'"$XDG_CONFIG_HOME"'}"' ]
    [ -x "$module/stage/bin/rendered-tool" ]
    [ ! -e "$module/stage/data/vendor-example" ]
    [ ! -e "$module/stage/build/ignored" ]
}

@test "required and optional render values propagate literally and invalidate outputs" {
    make_module stage
    run make_module stage CONTEXT_INPUT=changed "OPTIONAL_CONTEXT=builder's context" FIXTURE_VALUE=changed
    assert_success
    [ "$(sed -n '1p' "$module/stage/config/context.conf")" = "$XDG_CONFIG_HOME" ]
    [ "$(sed -n '2p' "$module/stage/config/context.conf")" = changed ]
    [ "$(sed -n '3p' "$module/stage/config/context.conf")" = "builder's context" ]
    [ "$(cat "$module/stage/config/rendered.conf")" = changed ]
    make_module check-required-export CONTEXT_INPUT=changed
}

@test "unchanged render context does not invoke the renderer again" {
    cat > "$work/m4" <<'SCRIPT'
#!/bin/sh
printf 'render\n' >> "$HOME/render-log"
exec m4 "$@"
SCRIPT
    mkdir -p "$HOME"
    chmod +x "$work/m4"
    make_module stage M4="$work/m4"
    cp "$HOME/render-log" "$work/first"
    make_module stage M4="$work/m4"
    cmp "$work/first" "$HOME/render-log"
}

@test "renderer flags invalidate templates even when values are unchanged" {
    printf 'M4_EXTRA\n' > "$module/src/config/flags.m4"
    make_module stage m4_flags=--define=M4_EXTRA=first
    [ "$(cat "$module/stage/config/flags")" = first ]
    make_module stage m4_flags=--define=M4_EXTRA=second
    [ "$(cat "$module/stage/config/flags")" = second ]
}

@test "rebuilding propagates executable distinction even when rendered bytes match" {
    make_module stage
    chmod a-x "$module/src/bin/rendered-tool.m4"
    # Explicit timestamps exercise our rebuild recipe without sleeping for Make.
    touch -t 200001010000 "$module/stage/bin/rendered-tool"
    make_module stage
    [ ! -x "$module/stage/bin/rendered-tool" ]
    chmod u+x "$module/src/bin/rendered-tool.m4"
    touch -t 200001010000 "$module/stage/bin/rendered-tool"
    make_module stage
    [ -x "$module/stage/bin/rendered-tool" ]
}

@test "prune removes obsolete public files and preserves private intermediates" {
    make_module stage
    mkdir -p "$module/stage/config/.private"
    printf stale > "$module/stage/config/stale"
    printf private > "$module/stage/.build/input"
    printf private > "$module/stage/config/.private/input"
    make_module stage
    [ ! -e "$module/stage/config/stale" ]
    [ -f "$module/stage/config/claimed" ]
    [ -f "$module/stage/.build/input" ]
    [ -f "$module/stage/config/.private/input" ]
}

@test "stage rejects undeclared output from module prerequisites" {
    run make_module -j4 stage ROGUE_OUTPUT=1
    assert_failure
    assert_output_contains 'undeclared staged output: stage/config/rogue.conf'
}

@test "inspect resolves destinations using the selected namespace root" {
    make_module stage
    run make_module inspect XDG_CONFIG_HOME="$work/custom"
    assert_success
    assert_output_contains "$(printf 'file\t0600\tstage/config/static.conf\tconfig/static.conf\t%s/static.conf' "$work/custom")"
}
