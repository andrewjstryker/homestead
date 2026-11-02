#!/usr/bin/env bats
# shellcheck source=tests/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"
setup() {
    setup_sandbox
    mkdir -p "$module/src/config"
    cat > "$module/Makefile" <<'MAKEFILE'
include ../_homestead/prelude.mk
FROM_DEFAULT ?= default
FROM_TABLE ?= default
FROM_COMMAND ?= default
DERIVED ?= ${XDG_DATA_HOME}/derived
include ../_homestead/homestead.mk
.PHONY: report
report:
	printf '%s|%s|%s|%s|%s|%s\n' '${FROM_DEFAULT}' '${FROM_TABLE}' '${FROM_COMMAND}' \
	  '${DERIVED}' "$${STALE-unset}" "$${FROM_TABLE-unset}"
MAKEFILE
    # The sandbox exports roots; direct make must not read any of them.
    unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME BIN_DIR LIBEXEC_DIR
}

report() {
    make --no-print-directory -s -C "$module" "$@" report
}

@test "direct make ignores inherited values; command line, table, and defaults decide" {
    printf 'FROM_TABLE=table\nFROM_COMMAND=table\nXDG_DATA_HOME=/srv/data\n' > "$module/.env"
    run env STALE=inherited FROM_DEFAULT=inherited FROM_TABLE=inherited XDG_DATA_HOME=/inherited \
        make --no-print-directory -s -C "$module" FROM_COMMAND=command report
    assert_success
    [ "$output" = 'default|table|command|/srv/data/derived|unset|table' ]
}

@test "the shared roots default from HOME, as the build floor" {
    run env XDG_DATA_HOME=/inherited make --no-print-directory -s -C "$module" report
    assert_success
    [ "$output" = "default|default|default|$HOME/.local/share/derived|unset|unset" ]
}

@test "ENV_FILE names another table, must exist when named, and may be empty" {
    printf 'FROM_TABLE=module\n' > "$module/.env"
    printf 'FROM_TABLE=collection table\n' > "$work/collection.env"
    run report ENV_FILE="$work/collection.env"
    assert_success
    [ "$output" = "default|collection table|default|$HOME/.local/share/derived|unset|collection table" ]
    run report ENV_FILE=
    assert_success
    [ "$output" = "default|default|default|$HOME/.local/share/derived|unset|unset" ]
    run report ENV_FILE="$work/absent.env"
    assert_failure
    assert_output_contains 'no such environment table'
    # An inherited ENV_FILE is ignored like any other value.
    run env ENV_FILE="$work/absent.env" make --no-print-directory -s -C "$module" report
    assert_success
    [ "$output" = "default|module|default|$HOME/.local/share/derived|unset|module" ]
}

@test "tables are validated as data before Make reads them" {
    printf '# fine\n\nFROM_TABLE=ok\nFROM_TABLE=twice\nlower=1\nQUOTED="x"\nREF=$(HOME)\nSPACE=x \nDESTDIR=/x\nLC_ALL=C\nMAKEFLAGS=-k\n' > "$module/.env"
    run report
    assert_failure
    for expected in '.env:4: FROM_TABLE: set more than once' '.env:5: expected NAME=value' \
        '.env:6: QUOTED: values cannot contain' '.env:7: REF: values cannot contain' \
        '.env:8: SPACE: trailing whitespace' '.env:9: DESTDIR: not a table input' \
        '.env:10: LC_ALL: not a table input' '.env:11: MAKEFLAGS: not a table input'; do
        assert_output_contains "$expected"
    done
}

@test "an empty table value is a value, and empty roots still fail" {
    printf 'FROM_TABLE=\n' > "$module/.env"
    run report
    assert_success
    [ "$output" = "default||default|$HOME/.local/share/derived|unset|" ]
    printf 'XDG_DATA_HOME=\n' > "$module/.env"
    run report
    assert_failure
    assert_output_contains 'XDG_DATA_HOME must not be empty'
}

@test "homestead.mk refuses to run without the prelude first" {
    printf 'include ../_homestead/homestead.mk\n' > "$module/Makefile"
    run make --no-print-directory -C "$module" show
    assert_failure
    assert_output_contains 'include prelude.mk'
}

@test "recursive make keeps the values its parent resolved" {
    printf 'FROM_TABLE=table\n' > "$module/.env"
    cat >> "$module/Makefile" <<'MAKEFILE'
.PHONY: nested
nested:
	FROM_DEFAULT=parent-export $(MAKE) -s report
MAKEFILE
    run make --no-print-directory -s -C "$module" FROM_COMMAND=command nested
    assert_success
    [ "$output" = "parent-export|table|command|$HOME/.local/share/derived|unset|table" ]
}
