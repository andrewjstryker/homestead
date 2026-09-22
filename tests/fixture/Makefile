PROTOCOL_MK ?= ../../protocol.mk

FIXTURE_CONFIG_ROOT ?= ${XDG_CONFIG_HOME}
config_root := ${FIXTURE_CONFIG_ROOT}

CONTEXT_INPUT ?= required-context
required_inputs := CONTEXT_INPUT
claimed_sources = ${src}/config/claimed.upper
claimed_outputs = ${stage}/config/claimed

FIXTURE_VALUE ?= rendered
m4_vars += FIXTURE_VALUE
links := config/static.conf

OPTIONAL_CONTEXT ?= optional-context
m4_vars += OPTIONAL_CONTEXT

STAGE_TOOL   ?= /bin/true
INSTALL_TOOL ?= /bin/true
SYNC_TOOL    ?= /bin/true
TRANSFORM_TOOL ?= $(shell command -v tr)

stage_tools   := STAGE_TOOL TRANSFORM_TOOL
install_tools := INSTALL_TOOL
sync_tools    := SYNC_TOOL

include ${PROTOCOL_MK}

${stage}/config/claimed: ${src}/config/claimed.upper
	mkdir -p '$(@D)'
	'${TRANSFORM_TOOL}' '[:lower:]' '[:upper:]' < '$<' > '$@'
	chmod --reference='$<' '$@'

.PHONY: check-required-export
check-required-export:
	test "$$CONTEXT_INPUT" = '${CONTEXT_INPUT}'

.PHONY: create-rogue-output
create-rogue-output: | prune
	mkdir -p '${stage}/config'
	printf 'undeclared\n' > '${stage}/config/rogue.conf'

stage: $(if ${ROGUE_OUTPUT},create-rogue-output)
