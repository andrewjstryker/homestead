#!/bin/sh
set -eu
here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
concern=$work/concern
mkdir -p "$concern/src/config" "$concern/vendor/data" "$concern/src/bin"
export PROTOCOL_MK=$root/protocol.mk
export HOME=$work/home
export XDG_CONFIG_HOME=$HOME/config XDG_DATA_HOME=$HOME/data
export XDG_STATE_HOME=$HOME/state XDG_CACHE_HOME=$HOME/cache BIN_DIR=$HOME/bin
cat > "$concern/Makefile" <<'MAKEFILE'
required_inputs := REQUIRED
REQUIRED ?= ready
links := config/example
include ${PROTOCOL_MK}
MAKEFILE
printf 'version one\n' > "$concern/src/config/example"
printf 'obsolete\n' > "$concern/src/config/obsolete"
printf 'vendor\n' > "$concern/vendor/data/payload"
printf '#!/bin/sh\nexit 0\n' > "$concern/src/bin/tool"
chmod +x "$concern/src/bin/tool"
run() { make --no-print-directory -C "$concern" "$@"; }
receipt=$concern/.homestead/receipt
tab=$(printf '\t')

# Preview and dry-run installs do not create receipt state.
run preview > "$work/preview"
run install DRY_RUN=1 > "$work/dry-install"
test ! -e "$receipt"
test ! -e "$XDG_CONFIG_HOME/example"
run install > "$work/install"
test -f "$receipt"
test "$(stat -c %a "$receipt")" = 600
test "$(wc -l < "$receipt")" -eq 4
hash=$(md5sum < "$XDG_CONFIG_HOME/example")
hash=${hash%% *}
grep -Fxq "$hash${tab}$XDG_CONFIG_HOME/example" "$receipt"
test -L "$HOME/.example"

# Unchanged files are recorded on every install, preserving the existing prefix.
cp "$receipt" "$work/first"
run install > "$work/reinstall"
head -n 4 "$receipt" > "$work/prefix"
cmp "$work/first" "$work/prefix"
test "$(wc -l < "$receipt")" -eq 8
cp "$receipt" "$work/before-preview"
run preview > "$work/preview-again"
run install DRY_RUN=1 > "$work/dry-again"
cmp "$receipt" "$work/before-preview"

# The latest MD5 wins; matching an older installed version does not suffice.
printf 'version two\n' > "$concern/src/config/example"
run clean
run install > "$work/new-version"
printf 'version one\n' > "$XDG_CONFIG_HOME/example"
# Source deletion and stage cleaning must not erase ownership history.
rm "$concern/src/config/obsolete"
run clean
run stage > "$work/prune"
test ! -e "$concern/stage/config/obsolete"
run clean
# Modified content and replacement symlinks survive; mode-only changes do not.
printf 'modified vendor\n' > "$XDG_DATA_HOME/payload"
chmod a-x "$BIN_DIR/tool"
cp "$receipt" "$work/before-uninstall"
run uninstall DRY_RUN=1 REQUIRED= M4= RSYNC= > "$work/dry-uninstall"
test -f "$XDG_CONFIG_HOME/obsolete"
test -f "$BIN_DIR/tool"
test -L "$HOME/.example"
cmp "$receipt" "$work/before-uninstall"
run uninstall REQUIRED= M4= RSYNC= > "$work/uninstall"
test ! -e "$concern/stage"
test -f "$XDG_CONFIG_HOME/example"
test -f "$XDG_DATA_HOME/payload"
test ! -e "$XDG_CONFIG_HOME/obsolete"
test ! -e "$BIN_DIR/tool"
test ! -L "$HOME/.example"
cmp "$receipt" "$work/before-uninstall"
run uninstall REQUIRED= > "$work/repeated-uninstall"
cmp "$receipt" "$work/before-uninstall"

# Restoring the latest installed bytes permits removal without any sources.
printf 'version two\n' > "$XDG_CONFIG_HOME/example"
rm -rf "$concern/src" "$concern/vendor"
run uninstall REQUIRED= > "$work/no-sources"
test ! -e "$XDG_CONFIG_HOME/example"
test -f "$XDG_DATA_HOME/payload"

# Missing or corrupt receipts fail before deleting even matching declared links.
ln -s "$XDG_CONFIG_HOME/example" "$HOME/.example"
mv "$receipt" "$work/saved-receipt"
if run uninstall > "$work/missing" 2>&1; then exit 1; fi
grep -q 'missing receipt' "$work/missing"
test -L "$HOME/.example"
cp "$work/saved-receipt" "$receipt"
printf 'not a receipt\n' >> "$receipt"
if run uninstall > "$work/corrupt" 2>&1; then exit 1; fi
grep -q 'invalid receipt record' "$work/corrupt"
test -L "$HOME/.example"
cp "$work/saved-receipt" "$receipt"

# A symlink replacing a receipted regular file must never be followed/deleted.
ln -s "$XDG_DATA_HOME/payload" "$XDG_CONFIG_HOME/example"
run uninstall > "$work/replacement-link"
test -L "$XDG_CONFIG_HOME/example"
rm "$XDG_CONFIG_HOME/example"

# DESTDIR keeps receipt history and uninstall separate from the live install.
mkdir -p "$concern/src/config"
printf 'live\n' > "$concern/src/config/example"
run install > "$work/live"
cp "$receipt" "$work/live-receipt"
staged=$work/destdir
run install DESTDIR="$staged" > "$work/staged"
test -f "$staged$receipt"
cmp "$receipt" "$work/live-receipt"
run uninstall DESTDIR="$staged" REQUIRED= > "$work/staged-uninstall"
test ! -e "$staged$XDG_CONFIG_HOME/example"
test -f "$XDG_CONFIG_HOME/example"
test -L "$HOME/.example"

# Namespace-root changes retain old destinations in the same receipt.
run install config_root="$HOME/other-config" links= > "$work/relocated"
run uninstall config_root="$HOME/other-config" links= > "$work/relocated-uninstall"
test ! -e "$HOME/other-config/example"
test ! -e "$XDG_CONFIG_HOME/example"

# A failed rsync invocation can write payload, but must not append its records.
export REAL_RSYNC
REAL_RSYNC=$(command -v rsync)
cat > "$work/fail-rsync" <<'SCRIPT'
#!/bin/sh
"$REAL_RSYNC" "$@" || exit
exit 23
SCRIPT
chmod +x "$work/fail-rsync"
cp "$receipt" "$work/before-failure"
if run install RSYNC="$work/fail-rsync" > "$work/failed-install" 2>&1; then exit 1; fi
cmp "$receipt" "$work/before-failure"

# No hidden dependency on staging tools; checksum checking has its own preflight.
if run uninstall MD5SUM= > "$work/missing-md5" 2>&1; then exit 1; fi
grep -q 'Missing tools needed to uninstall: MD5SUM' "$work/missing-md5"
test -f "$XDG_CONFIG_HOME/example"
# Earlier successful namespaces remain recorded if a later namespace fails.
mkdir -p "$concern/vendor/data"
printf 'new config\n' > "$concern/src/config/example"
printf 'failed vendor\n' > "$concern/vendor/data/failed"
run clean
cat > "$work/fail-data-rsync" <<'SCRIPT'
#!/bin/sh
"$REAL_RSYNC" "$@" || exit
for arg do
    case $arg in vendor/data/ | */vendor/data/) exit 23 ;; esac
done
SCRIPT
chmod +x "$work/fail-data-rsync"
cp "$receipt" "$work/before-partial"
if run install RSYNC="$work/fail-data-rsync" > "$work/partial" 2>&1; then exit 1; fi
count=$(wc -l < "$work/before-partial")
head -n "$count" "$receipt" > "$work/partial-prefix"
cmp "$work/before-partial" "$work/partial-prefix"
hash=$(md5sum < "$XDG_CONFIG_HOME/example")
hash=${hash%% *}
grep -Fxq "$hash${tab}$XDG_CONFIG_HOME/example" "$receipt"
if grep -F "$XDG_DATA_HOME/failed" "$receipt"; then exit 1; fi

# Repointed compatibility links are left alone independently of file receipts.
rm "$HOME/.example"
ln -s "$HOME/somewhere-else" "$HOME/.example"
run uninstall > "$work/repointed"
test -L "$HOME/.example"
test "$(readlink "$HOME/.example")" = "$HOME/somewhere-else"

# An empty concern still has a usable receipt; an explicit location is honored.
mkdir "$work/empty"
printf 'include ${PROTOCOL_MK}\n' > "$work/empty/Makefile"
make --no-print-directory -C "$work/empty" install RECEIPT=history.tsv
test -f "$work/empty/history.tsv"
test ! -s "$work/empty/history.tsv"
make --no-print-directory -C "$work/empty" uninstall RECEIPT=history.tsv

printf 'receipt installation and removal: PASS\n'
