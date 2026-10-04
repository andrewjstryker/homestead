#!/bin/sh
set -eu
here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
export HOME=$work/home XDG_CONFIG_HOME=$work/config XDG_DATA_HOME=$work/data
export XDG_STATE_HOME=$work/state XDG_CACHE_HOME=$work/cache BIN_DIR=$work/bin
export HOMESTEAD_ROOT=$work HOMESTEAD_MK=$root/homestead.mk CONFIG_ENV=$work/absent
export MODULES_FIRST=floor MODULES_LAST='shell
other-shell'
export EVENTS=$work/events
home=$root/home
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

# Stage collects failures in every phase, including first and last modules.
for selection in implicit explicit; do
    set --
    if [ "$selection" = explicit ]; then set -- floor middle other shell other-shell; fi
    for kind in preflight stage inspect; do
        : > "$EVENTS"
        case $kind in
            preflight) export FAIL_PREFLIGHT='floor middle'; expected='check-stage-tools' ;;
            stage) export FAIL_STAGE='floor middle shell'; expected=stage ;;
            inspect) export FAIL_INSPECT='floor middle'; expected=inspect ;;
        esac
        if "$home" stage "$@" >"$work/out" 2>&1; then
            printf 'stage accepted %s failure (%s)\n' "$kind" "$selection" >&2
            exit 1
        fi
        grep -q "FAILED ($expected): floor middle" "$work/out"
        grep -qx 'stage other' "$EVENTS"
        grep -qx 'stage other-shell' "$EVENTS"
        # Each eligible module stages once, even when composed consumers exist.
        test "$(grep -c '^stage other$' "$EVENTS")" -eq 1
        test "$(grep -c '^stage other-shell$' "$EVENTS")" -eq 1
        if grep -E '/(floor|middle)/' "$work/other-shell/received-fragments"; then exit 1; fi
        grep -q '/other/stage/config/env.d/other.sh' "$work/other-shell/received-fragments"
        unset FAIL_PREFLIGHT FAIL_STAGE FAIL_INSPECT
    done
    # Install and apply stop at any prerequisite failure, before any installation.
    for verb in install apply; do
        for kind in preflight stage inspect; do
            : > "$EVENTS"
            case $kind in
                preflight) export FAIL_PREFLIGHT='middle other'; expected='check-stage-tools' ;;
                stage) export FAIL_STAGE='middle other'; expected=stage ;;
                inspect) export FAIL_INSPECT='middle other'; expected=inspect ;;
            esac
            if "$home" "$verb" "$@" >"$work/out" 2>&1; then exit 1; fi
            grep -q "FAILED ($expected): middle$" "$work/out"
            if grep -E '^(install|sync) ' "$EVENTS"; then exit 1; fi
            if grep -q "FAILED ($expected): other" "$work/out"; then exit 1; fi
            case $kind in
                stage) if grep -qx 'stage other' "$EVENTS"; then exit 1; fi ;;
                inspect) if grep -qx 'inspect other' "$EVENTS"; then exit 1; fi ;;
            esac
            unset FAIL_PREFLIGHT FAIL_STAGE FAIL_INSPECT
        done
    done
done

# Without a consumer, staging still continues after ordinary Make failures.
: > "$EVENTS"
if FAIL_STAGE=middle "$home" stage middle other >"$work/no-consumer" 2>&1; then exit 1; fi
grep -qx 'stage other' "$EVENTS"
if grep -q '^inspect ' "$EVENTS"; then exit 1; fi

# Without consumers, installation can encounter a staging error inside Make's
# install target; it must still stop before the next module.
: > "$EVENTS"
if FAIL_STAGE=middle "$home" install middle other >"$work/install-no-consumer" 2>&1; then exit 1; fi
grep -q 'FAILED (install): middle' "$work/install-no-consumer"
if grep -qx 'stage other' "$EVENTS"; then exit 1; fi

# Dry-run and staged apply follow the same stop policy during installation.
for mode in dry-run destdir; do
    : > "$EVENTS"
    case $mode in
        dry-run) set -- --dry-run ;;
        destdir) set -- --destdir "$work/staged" ;;
    esac
    if FAIL_INSTALL=middle "$home" apply floor middle other shell "$@" >"$work/install-$mode" 2>&1; then exit 1; fi
    grep -q 'FAILED (install): middle' "$work/install-$mode"
    grep -qx 'install floor' "$EVENTS"
    if grep -E '^(install other|install shell|sync )' "$EVENTS"; then exit 1; fi
    if [ "$mode" = destdir ]; then
        test -s "$work/staged$work/floor/.homestead/receipt"
        test -f "$work/staged$XDG_CONFIG_HOME/env.d/floor.sh"
        test ! -e "$work/staged$XDG_CONFIG_HOME/env.d/other.sh"
    fi
done

# A clean stage returns success after earlier commands in this test failed.
: > "$EVENTS"
"$home" stage >"$work/success"
test "$(grep -c '^stage ' "$EVENTS")" -eq 5
cmp "$work/shell/received-fragments" "$work/other-shell/received-fragments"
printf 'collection failure policies: PASS\n'
