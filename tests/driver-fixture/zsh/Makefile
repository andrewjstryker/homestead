claimed_outputs := stage/config/composed.conf
include ${PROTOCOL_MK}

ZSH_TOOL ?= /bin/true
stage_tools += ZSH_TOOL

${stage}/config/composed.conf:
	mkdir -p '$(@D)'
	: > '$@'
	printf '%s\n' "$${ENV_FRAGMENTS-}" | while IFS= read -r fragment; do \
	  test -z "$$fragment" || cat "$$fragment" >> '$@'; \
	done

.PHONY: assert-installed
assert-installed:
	test -f '${XDG_CONFIG_HOME}/base.conf'
	test -z "$${EXPECT_MIDDLE-}" || test -f '${XDG_CONFIG_HOME}/middle.conf'
	test -f '${XDG_CONFIG_HOME}/zsh.conf'
	printf 'sync\n' >> '${SYNC_LOG}'

sync: assert-installed
