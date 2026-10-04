#!/usr/bin/env bats
# shellcheck source=tests/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"
setup() {
    setup_sandbox
    minimal_module
    printf 'required_inputs := REQUIRED\nREQUIRED ?= ready\nlinks := config/example\n' > "$module/Makefile"
    printf 'include ${HOMESTEAD_MK}\n' >> "$module/Makefile"
    mkdir -p "$module/vendor/data" "$module/src/bin"
    printf 'version one\n' > "$module/src/config/example"
    printf 'obsolete\n' > "$module/src/config/obsolete"
    printf vendor > "$module/vendor/data/payload"
    printf '#!/bin/sh\nexit 0\n' > "$module/src/bin/tool"
    chmod +x "$module/src/bin/tool"
    receipt=$module/.homestead/receipt
}

@test "preview and dry-run install create neither destinations nor receipts" {
    for action in preview 'install DRY_RUN=1'; do
        # Intentional word splitting selects the target and optional Make assignment.
        # shellcheck disable=SC2086
        run make_module $action
        assert_success
        [ ! -e "$module/.homestead" ]
        [ ! -e "$XDG_CONFIG_HOME" ]
        [ ! -L "$HOME/.example" ]
    done
}

@test "installation records unchanged files again and keeps receipts private" {
    make_module install
    [ "$(stat -c %a "$receipt")" = 600 ]
    cp "$receipt" "$work/first"
    make_module install
    cat "$work/first" "$work/first" > "$work/expected"
    cmp "$work/expected" "$receipt"
    make_module preview
    make_module install DRY_RUN=1
    cmp "$work/expected" "$receipt"
}

@test "uninstall uses latest bytes, preserves modifications, and works without sources or stage tools" {
    make_module install
    printf 'version two\n' > "$module/src/config/example"
    make_module clean
    make_module install
    printf 'version one\n' > "$XDG_CONFIG_HOME/example"
    printf modified > "$XDG_DATA_HOME/payload"
    chmod a-x "$BIN_DIR/tool"
    rm -rf "$module/src" "$module/vendor"
    make_module clean
    cp "$receipt" "$work/before"
    make_module uninstall REQUIRED= M4= RSYNC=
    [ "$(cat "$XDG_CONFIG_HOME/example")" = 'version one' ]
    [ "$(cat "$XDG_DATA_HOME/payload")" = modified ]
    [ ! -e "$XDG_CONFIG_HOME/obsolete" ]
    [ ! -e "$BIN_DIR/tool" ]
    [ ! -L "$HOME/.example" ]
    [ ! -e "$module/stage" ]
    cmp "$receipt" "$work/before"
    printf 'version two\n' > "$XDG_CONFIG_HOME/example"
    make_module uninstall REQUIRED=
    [ ! -e "$XDG_CONFIG_HOME/example" ]
    make_module uninstall REQUIRED=
    cmp "$receipt" "$work/before"
}

@test "dry-run uninstall leaves files, links, and receipt history untouched" {
    make_module install
    cp "$receipt" "$work/before"
    make_module uninstall DRY_RUN=1 REQUIRED= M4= RSYNC=
    [ -f "$XDG_CONFIG_HOME/example" ]
    [ -f "$BIN_DIR/tool" ]
    [ -L "$HOME/.example" ]
    cmp "$receipt" "$work/before"
}

@test "missing or malformed receipts prevent all removal including compatibility links" {
    make_module install
    mv "$receipt" "$work/saved"
    run make_module uninstall
    assert_failure
    assert_output_contains 'missing receipt'
    [ -L "$HOME/.example" ]
    [ -f "$XDG_CONFIG_HOME/example" ]
    cp "$work/saved" "$receipt"
    printf 'not a receipt\n' >> "$receipt"
    run make_module uninstall
    assert_failure
    assert_output_contains 'invalid receipt record'
    [ -L "$HOME/.example" ]
    [ -f "$XDG_CONFIG_HOME/example" ]
}

@test "replacement file symlinks and repointed compatibility links survive uninstall" {
    make_module install
    rm "$XDG_CONFIG_HOME/example" "$HOME/.example"
    ln -s "$XDG_DATA_HOME/payload" "$XDG_CONFIG_HOME/example"
    ln -s "$HOME/elsewhere" "$HOME/.example"
    make_module uninstall
    [ -L "$XDG_CONFIG_HOME/example" ]
    [ "$(readlink "$HOME/.example")" = "$HOME/elsewhere" ]
}

@test "DESTDIR isolates both payload and ownership history from a live install" {
    make_module install
    cp "$receipt" "$work/live-receipt"
    make_module install DESTDIR="$work/destdir"
    [ -f "$work/destdir$receipt" ]
    cmp "$receipt" "$work/live-receipt"
    make_module uninstall DESTDIR="$work/destdir" REQUIRED=
    [ ! -e "$work/destdir$XDG_CONFIG_HOME/example" ]
    [ -f "$XDG_CONFIG_HOME/example" ]
    [ -L "$HOME/.example" ]
}

@test "relocating a namespace retains old destinations for uninstall" {
    make_module install
    make_module install XDG_CONFIG_HOME="$HOME/other-config" links=
    make_module uninstall XDG_CONFIG_HOME="$HOME/other-config" links=
    [ ! -e "$HOME/other-config/example" ]
    [ ! -e "$XDG_CONFIG_HOME/example" ]
}

@test "failed transfers do not append records but earlier successful namespaces remain owned" {
    export REAL_RSYNC
    REAL_RSYNC=$(command -v rsync)
    cat > "$work/fail-rsync" <<'SCRIPT'
#!/bin/sh
"$REAL_RSYNC" "$@" || exit
for arg do
    case $arg in vendor/data/ | */vendor/data/) exit 23 ;; esac
done
SCRIPT
    chmod +x "$work/fail-rsync"
    run make_module install RSYNC="$work/fail-rsync"
    assert_failure
    [ -f "$XDG_DATA_HOME/payload" ]
    hash=$(md5sum < "$XDG_CONFIG_HOME/example")
    grep -Fxq "$(printf '%s\t%s' "${hash%% *}" "$XDG_CONFIG_HOME/example")" "$receipt"
    run grep -F "$XDG_DATA_HOME/payload" "$receipt"
    [ "$status" -eq 1 ]
    cp "$receipt" "$work/before"
    printf '#!/bin/sh\n"$REAL_RSYNC" "$@" || exit\nexit 23\n' > "$work/fail-rsync"
    run make_module install RSYNC="$work/fail-rsync"
    assert_failure
    cmp "$receipt" "$work/before"
}

@test "uninstall checksum preflight prevents removal" {
    make_module install
    run make_module uninstall MD5SUM=
    assert_failure
    assert_output_contains 'Missing tools needed to uninstall: MD5SUM'
    [ -f "$XDG_CONFIG_HOME/example" ]
    [ -L "$HOME/.example" ]
}

@test "an empty module still receives a usable receipt" {
    rm -rf "$module/src" "$module/vendor"
    make_module install links=
    [ -f "$receipt" ]
    [ ! -s "$receipt" ]
    make_module uninstall links=
}

@test "installation applies namespace, permission, vendor-link, and preservation policy" {
    printf 'public source\n' > "$module/src/config/public"
    chmod 644 "$module/src/config/public"
    ln -s payload "$module/vendor/data/alias"
    printf ignored > "$module/vendor/data/.private"
    mkdir -p "$XDG_CONFIG_HOME"
    printf unrelated > "$XDG_CONFIG_HOME/unrelated"
    make_module install
    [ "$(stat -c %a "$XDG_CONFIG_HOME/public")" = 600 ]
    [ "$(stat -c %a "$BIN_DIR/tool")" = 700 ]
    [ "$(cat "$XDG_DATA_HOME/alias")" = vendor ]
    [ ! -L "$XDG_DATA_HOME/alias" ]
    [ ! -e "$XDG_DATA_HOME/.private" ]
    [ "$(cat "$XDG_CONFIG_HOME/unrelated")" = unrelated ]
    [ "$(readlink "$HOME/.example")" = "$XDG_CONFIG_HOME/example" ]
}
