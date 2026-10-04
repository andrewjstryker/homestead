# Shared globals are consumed by Bats cases; status/output come from Bats run.
# shellcheck disable=SC2034,SC2154
# Bats owns the lifetime of BATS_TEST_TMPDIR; every case gets a fresh sandbox.
setup_sandbox() {
    repo_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
    work=$BATS_TEST_TMPDIR
    export HOME=$work/home XDG_CONFIG_HOME=$work/config XDG_DATA_HOME=$work/data
    export XDG_STATE_HOME=$work/state XDG_CACHE_HOME=$work/cache BIN_DIR=$work/bin
    export HOMESTEAD_MK=$repo_root/homestead.mk
    export CONFIG_ENV=$work/absent.env
    unset DESTDIR DRY_RUN ENV_FRAGMENTS
    module=$work/module
    home=$repo_root/home
}

fixture_module() {
    cp -R "$BATS_TEST_DIRNAME/fixture" "$module"
}

minimal_module() {
    mkdir -p "$module/src/config"
    printf 'include ${HOMESTEAD_MK}\n' > "$module/Makefile"
}

make_module() {
    make --no-print-directory -C "$module" "$@"
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
