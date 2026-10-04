#!/bin/sh
set -eu

here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
test_root=$(mktemp -d)
fixture=${test_root}/fixture
cp -R "${here}/fixture" "$fixture"
export HOMESTEAD_MK="${here}/../homestead.mk"
rendered_source=${fixture}/src/bin/rendered-tool.m4
plain_source=${fixture}/src/config/static.conf
claimed_source=${fixture}/src/config/claimed.upper
vendor_tool=${fixture}/vendor/bin/vendor-tool
m4_context=${fixture}/stage/.build/m4-context
tab=$(printf '\t')

restore() {
	chmod u+x,go-rwx "${rendered_source}"
	chmod u+x,go-rwx "${vendor_tool}"
	printf 'static\n' > "${plain_source}"
	printf 'claimed transformation\n' > "${claimed_source}"
	rm -f "${fixture}/vendor/config/static.conf"
	rm -f "${m4_context}"
	rm -f "${fixture}/stage/config/claimed"
	rm -f "${fixture}/stage/config/context.conf"
	rm -f "${fixture}/stage/config/runtime-name.conf"
	rm -rf "${test_root}"
}
trap restore EXIT HUP INT TERM

# Public installation roots use ordinary defaults, but an explicitly empty
# value is invalid and fails before any lifecycle target can use it.
for variable in \
	XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME BIN_DIR; do
	if make --no-print-directory -C "${fixture}" show "$variable=" \
	     >"${test_root}/empty-path" 2>&1; then
		printf 'expected an empty %s to fail\n' "$variable" >&2
		exit 1
	fi
	grep -q "$variable must not be empty" "${test_root}/empty-path"
done

# Required render inputs are staging requirements, not parse requirements.
# Diagnostics and cleanup remain available and show names a missing value;
# stage fails before pruning or otherwise mutating existing output.
make --no-print-directory -C "${fixture}" help CONTEXT_INPUT= >/dev/null
missing_show=$(make --no-print-directory -C "${fixture}" show CONTEXT_INPUT=)
printf '%s\n' "${missing_show}" | grep -q 'CONTEXT_INPUT.*(MISSING)'
make --no-print-directory -C "${fixture}" clean CONTEXT_INPUT=
mkdir -p "${fixture}/stage/config"
printf stale > "${fixture}/stage/config/stale"
if make --no-print-directory -C "${fixture}" stage CONTEXT_INPUT= \
	>"${test_root}/missing-input" 2>&1; then
	printf 'expected a missing required input to fail staging\n' >&2
	exit 1
fi
grep -q 'Missing required inputs needed to stage: CONTEXT_INPUT' \
	"${test_root}/missing-input"
test -f "${fixture}/stage/config/stale"

make --no-print-directory -C "${fixture}" clean
make --no-print-directory -j4 -C "${fixture}" stage

test "$(cat "${fixture}/stage/config/static.conf")" = static
test "$(cat "${fixture}/stage/config/claimed")" = 'CLAIMED TRANSFORMATION'
test ! -e "${fixture}/stage/config/claimed.upper"
test "$(cat "${fixture}/stage/config/rendered.conf")" = rendered
test "$(sed -n '1p' "${fixture}/stage/config/context.conf")" = \
    "${HOME}/.config"
test "$(sed -n '2p' "${fixture}/stage/config/context.conf")" = \
    required-context
test "$(sed -n '3p' "${fixture}/stage/config/context.conf")" = \
    optional-context
test "$(cat "${fixture}/stage/config/runtime-name.conf")" = \
    'XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-'"${HOME}"'/.config}"'
test -f "${fixture}/stage/data/example"
test -f "${fixture}/stage/config/env.d/fixture.sh"
test -x "${fixture}/stage/bin/rendered-tool"
test "$("${fixture}/stage/bin/rendered-tool")" = rendered
test ! -e "${fixture}/stage/data/vendor-example"
test ! -e "${fixture}/stage/build/ignored"
test -f "${m4_context}"
grep -q '^ *FIXTURE_VALUE=rendered$' "${m4_context}"
for variable in \
	M4 m4_flags HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME \
	XDG_CACHE_HOME BIN_DIR CONTEXT_INPUT OPTIONAL_CONTEXT FIXTURE_VALUE; do
	grep -q "^ *$variable=" "${m4_context}"
done
! grep -q '^ *PATH=' "${m4_context}"
make --no-print-directory -C "${fixture}" check-required-export
inspection=$(make --no-print-directory -C "${fixture}" inspect)
printf '%s\n' "${inspection}" | grep -q \
	"^file${tab}0600${tab}stage/config/static.conf${tab}config/static.conf${tab}${HOME}/.config/static.conf$"
custom_inspection=$(make --no-print-directory -C "${fixture}" inspect \
	XDG_CONFIG_HOME="${test_root}/custom-config")
printf '%s\n' "${custom_inspection}" | grep -q \
	"^file${tab}0600${tab}stage/config/static.conf${tab}config/static.conf${tab}${test_root}/custom-config/static.conf$"

# The phony reconciliation action leaves an identical real context untouched,
# so normal m4 targets remain current. A changed context invalidates them.
sleep 1
context_marker=${test_root}/context-marker
touch "${context_marker}"
make --no-print-directory -C "${fixture}" stage
test ! "${m4_context}" -nt "${context_marker}"
test ! "${fixture}/stage/config/rendered.conf" -nt "${context_marker}"

sleep 1
make --no-print-directory -C "${fixture}" stage FIXTURE_VALUE=changed
test "${m4_context}" -nt "${context_marker}"
test "$(cat "${fixture}/stage/config/rendered.conf")" = changed

make --no-print-directory -C "${fixture}" stage
test "$(cat "${fixture}/stage/config/rendered.conf")" = rendered

# Render values are transported through the context rather than embedded as
# shell literals. An apostrophe is data, not a recipe delimiter.
make --no-print-directory -C "${fixture}" stage \
	OPTIONAL_CONTEXT="builder's context"
test "$(sed -n '3p' "${fixture}/stage/config/context.conf")" = \
	"builder's context"
make --no-print-directory -C "${fixture}" stage

# Required inputs enter the render-variable set automatically; modules add
# optional render values through m4_vars.
sleep 1
required_marker=${test_root}/required-marker
touch "${required_marker}"
make --no-print-directory -C "${fixture}" stage CONTEXT_INPUT=changed
test "${m4_context}" -nt "${required_marker}"
grep -q '^ *CONTEXT_INPUT=changed$' "${m4_context}"
grep -q '^changed$' "${fixture}/stage/config/context.conf"
test "$(cat "${fixture}/stage/config/rendered.conf")" = rendered
make --no-print-directory -C "${fixture}" stage

# Each lifecycle phase checks only its declared tools. A failed stage preflight
# happens before prune, so even parallel Make cannot mutate the staged tree.
if make --no-print-directory -C "${fixture}" stage M4= \
	 >"${test_root}/homestead-stage-tool" 2>&1; then
	printf 'expected Homestead m4 requirement to survive immediate caller lists\n' >&2
	exit 1
fi
grep -q 'Missing tools needed to stage: M4' \
	"${test_root}/homestead-stage-tool"

printf stale > "${fixture}/stage/config/stale"
if make --no-print-directory -j4 -C "${fixture}" stage STAGE_TOOL= \
     >"${test_root}/stage-tool" 2>&1; then
	printf 'expected a missing stage tool to fail staging\n' >&2
	exit 1
fi
grep -q 'Missing tools needed to stage: STAGE_TOOL' "${test_root}/stage-tool"
test -f "${fixture}/stage/config/stale"
rm -f "${fixture}/stage/config/stale"

# A module-owned transformation can add its tool to the stage phase without
# creating a second preflight path.
printf stale > "${fixture}/stage/config/stale"
if make --no-print-directory -j4 -C "${fixture}" stage TRANSFORM_TOOL= \
     >"${test_root}/transform-tool" 2>&1; then
	printf 'expected a missing transformation tool to fail staging\n' >&2
	exit 1
fi
grep -q 'Missing tools needed to stage: TRANSFORM_TOOL' \
	"${test_root}/transform-tool"
test -f "${fixture}/stage/config/stale"
rm -f "${fixture}/stage/config/stale"

make --no-print-directory -C "${fixture}" stage INSTALL_TOOL= SYNC_TOOL=
make --no-print-directory -C "${fixture}" sync STAGE_TOOL= INSTALL_TOOL=

if make --no-print-directory -C "${fixture}" install RSYNC= \
	     DESTDIR="${test_root}" >"${test_root}/homestead-install-tool" 2>&1; then
	printf 'expected Homestead rsync requirement to survive immediate caller lists\n' >&2
	exit 1
fi
grep -q 'Missing tools needed to install: RSYNC' \
	"${test_root}/homestead-install-tool"

if make --no-print-directory -C "${fixture}" install INSTALL_TOOL= \
     DESTDIR="${test_root}" >"${test_root}/install-tool" 2>&1; then
	printf 'expected a missing install tool to fail installation\n' >&2
	exit 1
fi
grep -q 'Missing tools needed to install: INSTALL_TOOL' \
	"${test_root}/install-tool"

make --no-print-directory -C "${fixture}" install SYNC_TOOL= \
	DESTDIR="${test_root}/phase-isolation" >/dev/null

if make --no-print-directory -C "${fixture}" sync SYNC_TOOL= \
     >"${test_root}/sync-tool" 2>&1; then
	printf 'expected a missing sync tool to fail synchronization\n' >&2
	exit 1
fi
grep -q 'Missing tools needed to sync: SYNC_TOOL' "${test_root}/sync-tool"

if make --no-print-directory -C "${fixture}" check SYNC_TOOL= \
     >"${test_root}/all-tools" 2>&1; then
	printf 'expected the full preflight to cover sync tools\n' >&2
	exit 1
fi
grep -q 'Missing tools needed to sync: SYNC_TOOL' "${test_root}/all-tools"

# Make does not observe mode-only source changes. Once the source timestamp
# changes, the ordinary recipes synchronize the declared executable bit.
sleep 1
touch "${fixture}/stage/bin/rendered-tool"
chmod a-x "${rendered_source}"
make --no-print-directory -C "${fixture}" stage
test -x "${fixture}/stage/bin/rendered-tool"
sleep 1
touch "${rendered_source}"
make --no-print-directory -C "${fixture}" stage
test ! -x "${fixture}/stage/bin/rendered-tool"
sleep 1
touch "${fixture}/stage/bin/rendered-tool"
chmod u+x,go-rwx "${rendered_source}"
make --no-print-directory -C "${fixture}" stage
test ! -x "${fixture}/stage/bin/rendered-tool"
sleep 1
touch "${rendered_source}"
make --no-print-directory -C "${fixture}" stage
test -x "${fixture}/stage/bin/rendered-tool"

chmod u+x "${plain_source}"
make --no-print-directory -C "${fixture}" stage
test ! -x "${fixture}/stage/config/static.conf"
sleep 1
touch "${plain_source}"
make --no-print-directory -C "${fixture}" stage
test -x "${fixture}/stage/config/static.conf"
chmod a-x "${plain_source}"
make --no-print-directory -C "${fixture}" stage
test -x "${fixture}/stage/config/static.conf"
sleep 1
touch "${plain_source}"
make --no-print-directory -C "${fixture}" stage
test ! -x "${fixture}/stage/config/static.conf"

# Prune removes orphaned public files and ignores private intermediates.
mkdir -p "${fixture}/stage/.build" "${fixture}/stage/config/.private"
printf stale > "${fixture}/stage/config/stale"
printf private > "${fixture}/stage/.build/input"
printf private > "${fixture}/stage/config/.private/input"
make --no-print-directory -C "${fixture}" stage
test ! -e "${fixture}/stage/config/stale"
test -f "${fixture}/stage/config/claimed"
test -f "${fixture}/stage/.build/input"
test -f "${fixture}/stage/config/.private/input"

# Validation runs after module-added stage prerequisites, so a successful
# recipe cannot smuggle an undeclared public file into installation.
if make --no-print-directory -C "${fixture}" stage ROGUE_OUTPUT=1 \
	>"${test_root}/rogue-output" 2>&1; then
	printf 'expected undeclared staged output to fail validation\n' >&2
	exit 1
fi
grep -q 'undeclared staged output: stage/config/rogue.conf' \
	"${test_root}/rogue-output"
test -f "${fixture}/stage/config/rogue.conf"
make --no-print-directory -C "${fixture}" stage
test ! -e "${fixture}/stage/config/rogue.conf"

# Preview and install use the same namespace transfers. Uninstall removes only
# destinations whose bytes match the latest receipt, regardless of mode changes.
preview=$(make --no-print-directory -C "${fixture}" preview DESTDIR="${test_root}")
printf '%s\n' "${preview}" | grep -q 'static.conf'
printf '%s\n' "${preview}" | grep -q 'vendor-example'
printf '%s\n' "${preview}" | grep -q 'would link'
test ! -e "${test_root}${HOME}/.config/static.conf"
test ! -L "${test_root}${HOME}/.static.conf"

make --no-print-directory -C "${fixture}" install DESTDIR="${test_root}"
test -f "${test_root}${HOME}/.config/static.conf"
test "$(cat "${test_root}${HOME}/.config/claimed")" = \
    'CLAIMED TRANSFORMATION'
test -f "${test_root}${HOME}/.local/share/example"
test "$(cat "${test_root}${HOME}/.local/share/vendor-example")" = vendored
test -x "${test_root}${HOME}/.local/bin/rendered-tool"
test -x "${test_root}${HOME}/.local/bin/vendor-tool"
test ! -e "${test_root}${HOME}/.local/share/.ignored"
test ! -e "${test_root}${HOME}/build/ignored"
test "$(readlink "${test_root}${HOME}/.static.conf")" = \
    "${HOME}/.config/static.conf"

printf 'locally modified\n' > "${test_root}${HOME}/.local/share/example"
printf 'locally modified vendor\n' > \
  "${test_root}${HOME}/.local/share/vendor-example"
chmod u+x "${test_root}${HOME}/.config/static.conf"
uninstall=$(make --no-print-directory -C "${fixture}" uninstall DESTDIR="${test_root}")
printf '%s\n' "${uninstall}" | grep -q "left modified  ${test_root}${HOME}/.local/share/example"
printf '%s\n' "${uninstall}" | grep -q "left modified  ${test_root}${HOME}/.local/share/vendor-example"
printf '%s\n' "${uninstall}" | grep -q "removed ${test_root}${HOME}/.config/static.conf"
test -f "${test_root}${HOME}/.local/share/example"
test ! -e "${test_root}${HOME}/.config/static.conf"
test ! -L "${test_root}${HOME}/.static.conf"
test ! -e "${test_root}${HOME}/.config/rendered.conf"
test ! -e "${test_root}${HOME}/.config/claimed"
test ! -e "${test_root}${HOME}/.local/bin/rendered-tool"
test -f "${test_root}${HOME}/.local/share/vendor-example"
test ! -e "${test_root}${HOME}/.local/bin/vendor-tool"

trap - EXIT HUP INT TERM
restore
printf 'Homestead staging and lifecycle: PASS\n'
