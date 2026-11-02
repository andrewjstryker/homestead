# Shared globals are consumed by Bats cases; status/output come from Bats run.
# shellcheck disable=SC2034,SC2154
# Bats owns the lifetime of BATS_TEST_TMPDIR; every case gets a fresh sandbox.
setup_sandbox() {
    repo_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
    work=$BATS_TEST_TMPDIR
    export HOME=$work/home XDG_CONFIG_HOME=$work/config XDG_DATA_HOME=$work/data
    export XDG_STATE_HOME=$work/state XDG_CACHE_HOME=$work/cache BIN_DIR=$work/bin LIBEXEC_DIR=$work/libexec
    unset DESTDIR DRY_RUN ENV_FRAGMENTS ENV_FILE
    # Modules include ../_homestead/, as they do in a collection.
    ln -s "$repo_root" "$work/_homestead"
    module=$work/module
    home=$repo_root/home
    # Modules ignore inherited values. drive and make_module pass these names,
    # at their values when they run; cases append the inputs they need.
    drive_vars=(XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
        BIN_DIR LIBEXEC_DIR)
}

# Run the driver with a table holding drive_vars. Leading NAME=value arguments
# add to the table and replace sandbox values; HOMESTEAD_ROOT becomes --root.
drive() {
    local name table=$work/drive.env extra=()
    while [[ $# -gt 0 && $1 =~ ^[A-Z_][A-Z0-9_]*= ]]; do
        extra+=("$1")
        shift
    done
    : > "$table"
    for name in "${drive_vars[@]}"; do
        [ "$name" != HOMESTEAD_ROOT ] && [ -n "${!name+x}" ] || continue
        [[ " ${extra[*]%%=*} " == *" $name "* ]] && continue
        printf '%s=%s\n' "$name" "${!name}" >> "$table"
    done
    [ "${#extra[@]}" -eq 0 ] || printf '%s\n' "${extra[@]}" >> "$table"
    "$home" ${HOMESTEAD_ROOT:+--root "$HOMESTEAD_ROOT"} --env "$table" "$@"
}

# Link a collection's shared Homestead checkout to this one.
collection_homestead() {
    ln -s "$repo_root" "$1/_homestead"
}

fixture_module() {
    cp -R "$BATS_TEST_DIRNAME/fixture" "$module"
}

minimal_module() {
    mkdir -p "$module/src/config"
    printf 'include ../_homestead/prelude.mk\ninclude ../_homestead/homestead.mk\n' > "$module/Makefile"
}

# Sandbox roots are command-line inputs, as a test passes them.
make_module() {
    local name roots=()
    for name in "${drive_vars[@]}"; do
        [ -n "${!name+x}" ] && roots+=("$name=${!name}")
    done
    make --no-print-directory -C "$module" "${roots[@]}" "$@"
}

assert_success() {
    if [ "$status" -ne 0 ]; then
        printf 'expected success, got %s\n%s\n' "$status" "$output" >&2
        return 1
    fi
}

assert_failure() {
    if [ "$status" -eq 0 ]; then
        printf 'expected failure\n%s\n' "$output" >&2
        return 1
    fi
}

assert_output_contains() {
    if [[ "$output" != *"$1"* ]]; then
        printf 'expected output to contain: %s\nactual output:\n%s\n' "$1" "$output" >&2
        return 1
    fi
}
