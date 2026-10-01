#!/bin/sh
set -eu

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "${here}/.." && pwd)
fixture=${here}/driver-fixture
test_root=$(mktemp -d)

restore() {
	rm -rf "${test_root}"
}
trap restore EXIT HUP INT TERM

cp -R "${fixture}/." "${test_root}/"

export PROTOCOL_MK="${repo_root}/protocol.mk"
export HOME="${test_root}/home-dir"
export XDG_CONFIG_HOME="${test_root}/live/config"
export XDG_DATA_HOME="${test_root}/live/data"
export XDG_STATE_HOME="${test_root}/live/state"
export XDG_CACHE_HOME="${test_root}/live/cache"
export BIN_DIR="${test_root}/live/bin"
export SYNC_LOG="${test_root}/sync.log"
export CONFIG_ENV="${test_root}/absent.env"

export HOMESTEAD_ROOT="${test_root}"
export CONCERNS_FIRST=base
export CONCERNS_LAST=zsh
home=${repo_root}/home

# Explicit selection is reordered by collection policy.
show=$("${home}" show zsh middle base)
headings=$(printf '%s\n' "${show}" | sed -n 's/^==> \([^:]*\): show$/\1/p')
test "${headings}" = "$(printf 'base\nmiddle\nzsh')"
custom_show=$(CONCERNS_FIRST=middle CONCERNS_LAST=base \
	"${home}" show zsh middle base)
custom_headings=$(printf '%s\n' "${custom_show}" | \
	sed -n 's/^==> \([^:]*\): show$/\1/p')
test "${custom_headings}" = "$(printf 'middle\nzsh\nbase')"

# A missing tool in any selected concern blocks the entire install phase.
if REQUIRED_TOOL='' "${home}" install base middle \
     >"${test_root}/preflight.out" 2>&1; then
	printf 'expected install preflight to fail\n' >&2
	exit 1
fi
grep -q 'FAILED (check-install-tools): middle' "${test_root}/preflight.out"
test ! -e "${XDG_CONFIG_HOME}/base.conf"

# Installation failures stop immediately for both selection forms and commands.
for verb in install apply; do
    for selection in implicit explicit; do
        rm -rf "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${XDG_STATE_HOME}" \
            "${XDG_CACHE_HOME}" "${BIN_DIR}"
        rm -f "${SYNC_LOG}"
        set --
        if [ "$selection" = explicit ]; then set -- base middle runtime-fail zsh; fi
        if AVAILABILITY_INPUT=ready FAIL_INSTALL=1 "${home}" "$verb" "$@" \
            >"${test_root}/runtime-failure.out" 2>&1; then
            printf 'expected %s %s installation failure\n' "$selection" "$verb" >&2
            exit 1
        fi
        grep -q 'FAILED (install): runtime-fail' "${test_root}/runtime-failure.out"
        test -f "${XDG_CONFIG_HOME}/base.conf"
        test -f "${XDG_CONFIG_HOME}/middle.conf"
        test -s "${test_root}/base/.homestead/receipt"
        test ! -e "${XDG_CONFIG_HOME}/zsh.conf"
        test ! -e "${SYNC_LOG}"
        if grep -q '^==> zsh: install$' "${test_root}/runtime-failure.out"; then exit 1; fi
    done
done

# apply installs the whole selection before any sync recipe runs. The last
# concern receives composed fragments from the effective preceding manifests.
rm -f "${SYNC_LOG}"
EXPECT_MIDDLE=1 "${home}" apply base middle zsh >"${test_root}/apply.out"
test "$(cat "${SYNC_LOG}")" = sync
printf 'BASE_FRAGMENT=base\nMIDDLE_FRAGMENT=middle\n' >"${test_root}/expected-fragments"
cmp "${test_root}/expected-fragments" "${test_root}/zsh/stage/config/composed.conf"

# A staged apply prefixes all writes and omits the live synchronization pass.
rm -f "${SYNC_LOG}"
destdir=${test_root}/destdir
"${home}" apply --destdir "${destdir}" base middle zsh \
	>"${test_root}/destdir.out"
test -f "${destdir}${XDG_CONFIG_HOME}/base.conf"
test -f "${destdir}${XDG_CONFIG_HOME}/middle.conf"
test -f "${destdir}${XDG_CONFIG_HOME}/zsh.conf"
test ! -e "${SYNC_LOG}"
grep -q '^Sync skipped for staged apply.$' "${test_root}/destdir.out"

# Implicit selection also treats every preflight failure as fatal.
rm -rf "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${XDG_STATE_HOME}" \
    "${XDG_CACHE_HOME}" "${BIN_DIR}"
if AVAILABILITY_INPUT=ready REQUIRED_TOOL='' "${home}" install \
    >"${test_root}/implicit-failure.out" 2>&1; then
    printf 'expected implicit preflight failure\n' >&2
    exit 1
fi
grep -q 'FAILED (check-install-tools): middle' "${test_root}/implicit-failure.out"
test ! -e "${XDG_CONFIG_HOME}/base.conf"
test ! -e "${XDG_CONFIG_HOME}/middle.conf"
test ! -e "${XDG_CONFIG_HOME}/zsh.conf"

# Either anchor failing preflight makes the implicit operation fail before any
# selected concern mutates its destination.
rm -rf "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${XDG_STATE_HOME}" \
	"${XDG_CACHE_HOME}" "${BIN_DIR}"
if BASE_TOOL='' "${home}" install >"${test_root}/base-fatal.out" 2>&1; then
	printf 'implicit Base failure was not fatal\n' >&2
	exit 1
fi
grep -q 'FAILED (check-stage-tools): base' "${test_root}/base-fatal.out"
test ! -e "${XDG_CONFIG_HOME}/zsh.conf"

if AVAILABILITY_INPUT=ready ZSH_TOOL='' "${home}" install >"${test_root}/zsh-fatal.out" 2>&1; then
	printf 'implicit Zsh failure was not fatal\n' >&2
	exit 1
fi
grep -q 'FAILED (check-stage-tools): zsh' "${test_root}/zsh-fatal.out"
test ! -e "${XDG_CONFIG_HOME}/base.conf"

# Stage continues with other concerns, excludes failed producers, and fails overall.
if "${home}" stage >"${test_root}/unavailable-warning.out" 2>&1; then
	printf 'implicit stage failure returned success\n' >&2
	exit 1
fi
grep -q 'FAILED (check-stage-tools): unavailable' \
	"${test_root}/unavailable-warning.out"
if grep -q 'UNAVAILABLE_FRAGMENT' \
	"${test_root}/zsh/stage/config/composed.conf"; then
	printf 'failed concern fragment entered composition\n' >&2
	exit 1
fi

# Explicit stage selection uses the same failure status.
if AVAILABILITY_INPUT='' "${home}" stage unavailable \
	>"${test_root}/unavailable-explicit.out" 2>&1; then
	printf 'explicit unavailable concern failure was not fatal\n' >&2
	exit 1
fi
grep -q 'FAILED (check-stage-tools): unavailable' \
	"${test_root}/unavailable-explicit.out"
grep -q 'Missing required inputs needed to stage: AVAILABILITY_INPUT' \
	"${test_root}/unavailable-explicit.out"

# Shared destinations fail check even if each concern succeeds independently.
if "${home}" check collision-a collision-b >"${test_root}/collision.out" 2>&1; then
    printf 'expected destination collision to fail\n' >&2
    exit 1
fi
grep -q 'destination collision:.*shared.sh' "${test_root}/collision.out"

# Independent concern failures are aggregated rather than stopping traversal.
if "${home}" check fail-a fail-b >"${test_root}/fail.out" 2>&1; then
	printf 'expected concern checks to fail\n' >&2
	exit 1
fi
grep -q 'FAILED (check): fail-a fail-b' "${test_root}/fail.out"

# The same failures are warnings under implicit discovery.
if "${home}" check >"${test_root}/implicit-check.out" 2>&1; then
	printf 'implicit destination collisions should fail\n' >&2
	exit 1
fi
grep -q 'WARNING (check): fail-a fail-b' \
	"${test_root}/implicit-check.out"

# Test is a driver convenience, not a protocol verb. Concerns with no test
# target are skipped; a concern-owned target runs and obeys normal severity.
"${home}" test >"${test_root}/test.out"
grep -q '^==> middle: test$' "${test_root}/test.out"
grep -q 'test (skipped: no test target)' "${test_root}/test.out"
if FAIL_TEST=1 "${home}" test middle >"${test_root}/test-fail.out" 2>&1; then
	printf 'explicit concern test failure was not fatal\n' >&2
	exit 1
fi
grep -q 'FAILED (test): middle' "${test_root}/test-fail.out"

# Infrastructure is excluded from both implicit and explicit selection.
mkdir -p "${test_root}/_homestead" "${test_root}/.private"
printf '$(error infrastructure must never be parsed)\n' > "${test_root}/_homestead/Makefile"
cp "${test_root}/_homestead/Makefile" "${test_root}/.private/Makefile"
"${home}" show >"${test_root}/discovery.out"
for private in _homestead .private; do
    if "${home}" show "$private" >"${test_root}/private.out" 2>&1; then
        printf 'excluded concern accepted: %s\n' "$private" >&2
        exit 1
    fi
    grep -q 'no such concern repository' "${test_root}/private.out"
done

# The collection root is independent of code location, and --root wins over env.
collection="${test_root}/other collection"
mkdir -p "$collection"
ln -s "${test_root}/middle" "$collection/linked"
HOMESTEAD_ROOT=/nonexistent "${home}" --root "$collection" show linked >"${test_root}/root.out"
grep -q '^==> linked: show$' "${test_root}/root.out"
(cd "$collection" && unset HOMESTEAD_ROOT && "${home}" show linked) >"${test_root}/cwd.out"
grep -q '^==> linked: show$' "${test_root}/cwd.out"
CONCERNS_FIRST='' CONCERNS_LAST='' "${home}" show zsh base middle >"${test_root}/neutral.out"
headings=$(sed -n 's/^==> \([^:]*\): show$/\1/p' "${test_root}/neutral.out")
test "$headings" = "$(printf 'zsh\nbase\nmiddle')"

# Driver and Make agree that explicitly empty roots are invalid.
if XDG_CONFIG_HOME='' "${home}" show base >"${test_root}/empty.out" 2>&1; then
    printf 'driver accepted an empty installation root\n' >&2
    exit 1
fi
grep -q 'XDG_CONFIG_HOME must not be empty' "${test_root}/empty.out"

# Equal relative paths with distinct resolved roots do not collide.
printf '\nconfig_root = ${XDG_CONFIG_HOME}/separate\n' >>"${test_root}/collision-b/Makefile"
"${home}" check collision-a collision-b >"${test_root}/separate.out"

# Compatibility links and file/ancestor conflicts share the destination space.
mkdir -p "${test_root}/linker/src/config" "${test_root}/descendant/src/config/node"
printf link >"${test_root}/linker/src/config/item"
printf child >"${test_root}/descendant/src/config/node/child"
cat >"${test_root}/linker/Makefile" <<'MAKEFILE'
links := config/item
include ${PROTOCOL_MK}
link_of = ${XDG_CONFIG_HOME}/node
MAKEFILE
cat >"${test_root}/descendant/Makefile" <<'MAKEFILE'
include ${PROTOCOL_MK}
MAKEFILE
if "${home}" check linker descendant >"${test_root}/ancestor.out" 2>&1; then
    printf 'expected link/ancestor conflict to fail\n' >&2
    exit 1
fi
grep -q 'destination collision:.*node' "${test_root}/ancestor.out"
"${home}" check base middle >"${test_root}/valid.out"

# Uninstall uses receipts even when the concern can no longer stage or inspect.
cat >>"${test_root}/middle/Makefile" <<'MAKEFILE'
.PHONY: forbidden-build
forbidden-build:
	false
check-stage-tools inspect: forbidden-build
MAKEFILE
"${home}" uninstall middle >"${test_root}/uninstall.out"
test ! -e "${XDG_CONFIG_HOME}/middle.conf"

trap - EXIT HUP INT TERM
restore
printf 'collection driver lifecycle: PASS\n'
