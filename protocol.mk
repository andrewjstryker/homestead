# protocol.mk -- the shared home concern protocol
#
# src is the first-party declaration. Every unclaimed non-hidden path below it
# has the same relative path below stage, except that a final .m4 suffix is
# removed. Concerns claim inputs and publish outputs for other transformations.
# vendor is the third-party declaration: mapped namespace directories below it
# are installed directly and are never copied into stage. Dot-prefixed paths in
# either tree, and unmapped vendor directories such as vendor/build, are private.

homestead_mk := $(lastword ${MAKEFILE_LIST})
PROTOCOL_MK  ?= ${homestead_mk}
PROTOCOL_BIN ?= $(patsubst %/,%,$(dir ${PROTOCOL_MK}))/bin

ifeq ($(origin SHELL),default)
SHELL := /bin/sh
endif
ifeq ($(origin .SHELLFLAGS),default)
.SHELLFLAGS := -eu -c
endif
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:
.SILENT:

define nl


endef

# Environment -----------------------------------------------------------------

XDG_CONFIG_HOME ?= ${HOME}/.config
XDG_DATA_HOME   ?= ${HOME}/.local/share
XDG_STATE_HOME  ?= ${HOME}/.local/state
XDG_CACHE_HOME  ?= ${HOME}/.cache
BIN_DIR         ?= ${HOME}/.local/bin
required_inputs ?=

path_vars := \
  XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME BIN_DIR

require_nonempty = $(if $(strip $($1)),,$(error $1 must not be empty))
$(foreach v,HOME ${path_vars},$(call require_nonempty,$v))

export ${path_vars} ${required_inputs}

# Installation history is independent of generated staging state. Staged
# installs prefix the receipt location as well as payload destinations.
RECEIPT ?= ${CURDIR}/.homestead/receipt
$(call require_nonempty,RECEIPT)
receipt_file = $(if ${DESTDIR},$(abspath ${DESTDIR}))$(abspath ${RECEIPT})
receipt_destdir = $(if ${DESTDIR},$(abspath ${DESTDIR}))

DESTDIR ?=

# Tools and caller inputs ------------------------------------------------------

M4    ?= $(shell command -v m4)
RSYNC ?= $(shell command -v rsync)
MD5SUM ?= $(shell command -v md5sum)
m4_vars ?=

# Tool lists contain variable names rather than commands. Wrappers extend the
# phase in which a tool is first required; the aggregate is diagnostic only.
stage_tools   ?=
install_tools ?=
uninstall_tools ?=
sync_tools    ?=
protocol_stage_tools   = $(if $(strip ${m4_sources}),M4)
protocol_install_tools = RSYNC
protocol_uninstall_tools = MD5SUM
effective_stage_tools   = ${stage_tools} ${protocol_stage_tools}
effective_install_tools = ${install_tools} ${protocol_install_tools}
effective_uninstall_tools = ${uninstall_tools} ${protocol_uninstall_tools}
effective_sync_tools    = ${sync_tools}
tools = $(sort \
  ${effective_stage_tools} ${effective_install_tools} ${effective_sync_tools} ${effective_uninstall_tools})

missing_tools = $(strip $(foreach v,$1,$(if $(strip $($v)),,$v)))
missing_inputs = $(strip \
  $(foreach v,${required_inputs},$(if $(strip $($v)),,$v)))

# Non-file inputs available to ordinary m4 templates. Required staging inputs
# participate automatically; wrappers extend the set with m4_vars. Every value
# is recorded under its Make variable name and exposed to templates with an
# M4_ prefix. Keeping build macros out of the runtime namespace lets a template
# use ordinary shell/configuration names without capture-and-undefine tricks.
m4_context_vars = \
  XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME BIN_DIR \
  ${required_inputs}
m4_render_vars = $(sort ${m4_context_vars} ${m4_vars})

# Values travel through the reconciled context file. Only their names enter the
# recipe command line, so shell syntax in a value cannot alter the command.
m4_define_args = $(foreach v,${m4_render_vars},--define-context=$v=M4_$v)

# Renderer identity and behavior invalidate templates but are not themselves
# template variables. M4FLAGS is reserved for m4 options such as include paths.
m4_context_content = \
  M4=${M4}${nl} \
  M4FLAGS=${M4FLAGS}${nl} \
  HOME=${HOME}${nl} \
  $(foreach v,${m4_render_vars},$v=$($v)${nl})

export M4_CONTEXT = ${m4_context_content}
export M4_CONTEXT_FILE = ${m4_context}

define check_tools
	$(if $(call missing_tools,$1),\
	  $(error Missing tools needed to $2: $(call missing_tools,$1)))
endef

.PHONY: check-required-inputs check-stage-tool-paths
.PHONY: check-stage-tools check-install-tools check-sync-tools
.PHONY: check-uninstall-tools
check-uninstall-tools:
	$(call check_tools,${effective_uninstall_tools},uninstall)

.PHONY: check-tools #> Check every declared tool requirement
check-required-inputs:
	$(if ${missing_inputs},\
	  $(error Missing required inputs needed to stage: ${missing_inputs}))

check-stage-tool-paths:
	$(call check_tools,${effective_stage_tools},stage)

check-stage-tools: check-declarations check-required-inputs check-stage-tool-paths

check-install-tools:
	$(call check_tools,${effective_install_tools},install)

check-sync-tools:
	$(call check_tools,${effective_sync_tools},sync)

check-tools: check-stage-tool-paths check-install-tools check-sync-tools check-uninstall-tools

# Source declaration and staged manifest --------------------------------------

src    ?= src
stage  ?= stage
vendor ?= vendor
claimed_sources ?=
claimed_outputs ?=

# GNU make's wildcard excludes dot entries. That is intentional: a dot-prefixed
# directory is private wherever it appears and cannot become installed payload.
rwildcard = \
  $(filter-out $(patsubst %/,%,$(wildcard $1*/)),$(wildcard $1$2)) \
  $(foreach d,$(wildcard $1*/),$(call rwildcard,$d,$2))

rdirectories = $(wildcard $1*/) \
  $(foreach d,$(wildcard $1*/),$(call rdirectories,$d))

source_excludes   := %~ %.orig %.rej
discovered_sources = $(filter-out ${source_excludes},$(call rwildcard,${src}/,*))
sources           = $(filter-out ${claimed_sources},${discovered_sources})
source_dirs      = $(patsubst %/,%,$(call rdirectories,${src}/))
m4_sources       = $(filter %.m4,${sources})
plain_sources    = $(filter-out ${m4_sources},${sources})

staged_files = \
  $(patsubst ${src}/%,${stage}/%,${plain_sources}) \
  $(patsubst ${src}/%.m4,${stage}/%,${m4_sources}) \
  ${claimed_outputs}
staged_dirs = $(patsubst ${src}/%,${stage}/%,${source_dirs})
staged      = ${staged_dirs} ${staged_files}

stage_files = $(patsubst ${stage}/%,%,${staged_files})

# The context reconciler runs before stage realizes its outputs. It replaces a
# real private file only when the renderer or its expanded flags change. That
# file is a normal prerequisite of every ordinary template, bridging values
# which Make cannot otherwise see into its timestamp graph.
m4_context := ${stage}/.build/m4-context

.PHONY: update-m4-context
update-m4-context: check-stage-tools
	$(if $(strip ${m4_sources}),${PROTOCOL_BIN}/m4-context '${m4_context}',:)

${m4_context}: update-m4-context ;

${stage}/%: ${src}/%.m4 ${m4_context}
	M4='${M4}' ${PROTOCOL_BIN}/gen '$@' '$<' ${M4FLAGS} ${m4_define_args}

${stage}/%: ${src}/%
	mkdir -p '$(@D)'
	cp -p '$<' '$@'

# Pruning precedes every public staged path. The order-only edge keeps prune's
# phony status from making otherwise-current outputs rebuild.
.PHONY: prune
prune: check-stage-tools
	${PROTOCOL_BIN}/prune '${stage}' ${stage_expected}

stage_expected = ${staged}
stage_expected_dirs = ${staged_dirs}
stage_expected_files = ${staged_files}

ifneq ($(strip ${staged_files}),)
$(sort ${staged_files}): | prune
endif

.PHONY: stage #> Prune and incrementally realize the complete staged manifest
stage: prune ${staged_files}
	$(if ${staged_dirs},mkdir -p ${staged_dirs},:)
	${PROTOCOL_BIN}/validate-stage '${stage}' ${stage_expected_dirs} -- ${stage_expected_files}

# Namespace mapping -----------------------------------------------------------

namespaces := config data state cache bin

# Vendored trees can be large. A single find per namespace avoids expanding a
# recursive Make wildcard expression for every directory. As elsewhere in the
# protocol, declaration paths containing whitespace are unsupported.
vendor_sources = $(filter-out ${source_excludes},\
  $(foreach n,${namespaces},$(shell \
    if [ -d '${vendor}/$n' ]; then \
      find '${vendor}/$n' -name '.*' -prune -o \
        \( -type f -o -type l \) -print; \
    fi)))
declared_vendor_files = $(patsubst ${vendor}/%,%,${vendor_sources})
vendor_files = ${declared_vendor_files}

# The effective manifest is generated first-party output plus mapped vendored
# payload. vendor/build and all other unmapped vendor paths are build inputs.
files = ${stage_files} ${vendor_files}
effective_links = ${links}

config_root ?= ${XDG_CONFIG_HOME}
data_root   ?= ${XDG_DATA_HOME}
state_root  ?= ${XDG_STATE_HOME}
cache_root  ?= ${XDG_CACHE_HOME}
bin_root    ?= ${BIN_DIR}

namespace_of = $(firstword $(subst /, ,$1))
relative_of  = $(patsubst $(call namespace_of,$1)/%,%,$1)
root_of      = $($(call namespace_of,$1)_root)
installed_of = $(call root_of,$1)/$(call relative_of,$1)

claimed_files = $(patsubst ${stage}/%,%,${claimed_outputs})
source_of   = $(firstword $(wildcard ${src}/$1 ${src}/$1.m4))
manifest_of = $(if $(filter $1,${vendor_files}),${vendor}/$1,${stage}/$1)
declared_by = $(if $(filter $1,${vendor_files}),${vendor}/$1,$(if $(filter $1,${claimed_files}),${stage}/$1,$(call source_of,$1)))
mode_of     = $(if $(shell test -x '$(call declared_by,$1)' && echo x),0700,0600)

# A link names its manifest path. link_of adapts that path to the legacy place
# the application insists on; concerns override it when the default
# ~/.<basename> convention does not fit.
link_of = ${HOME}/.$(notdir $1)

# Declaration validation -------------------------------------------------------

# Validate the lists before Make's target graph or sort can hide duplicates.
# Only enumerate duplicate names when the counts differ (vendor lists can be
# large). Paths follow the same whitespace/Make-pattern limitations as manifests.
declaration_duplicates = $(if $(filter $(words $1),$(words $(sort $1))),,\
  $(sort $(foreach f,$1,$(if $(word 2,$(filter $f,$1)),$f))))

# Parent directory names, using only Make's path functions; no filesystem walk.
declaration_parents = $(if $(filter ./ /,$(dir $1)),,\
  $(patsubst %/,%,$(dir $1)) \
  $(call declaration_parents,$(patsubst %/,%,$(dir $1))))

.PHONY: check-declarations #> Reject conflicting declared manifest paths
check-declarations:
	$(eval homestead_decl_files := ${stage_files} ${vendor_files})
	$(eval homestead_decl_duplicates := $(call declaration_duplicates,${homestead_decl_files}))
	$(if ${homestead_decl_duplicates},$(error Duplicate manifest files: ${homestead_decl_duplicates}))
	$(eval homestead_decl_dirs := $(sort \
	  $(patsubst ${stage}/%,%,${staged_dirs}) \
	  $(foreach f,${homestead_decl_files},$(call declaration_parents,$f))))
	$(eval homestead_decl_conflicts := $(filter ${homestead_decl_files},${homestead_decl_dirs}))
	$(if ${homestead_decl_conflicts},$(error Manifest paths declared as both file and directory: ${homestead_decl_conflicts}))

# Transfer --------------------------------------------------------------------

# Content and permissions are authoritative; timestamps are not. This chmod
# removes group/world access without changing the source's owner-executable bit.
rsync_flags := \
  --recursive --checksum --perms --itemize-changes --mkpath \
  --chmod=u+rw,go-rwx

define transfer_stage
$(foreach n,${namespaces},\
  $(if $(wildcard ${stage}/$n/.),\
    RSYNC='${RSYNC}' DRY_RUN='$1' ${PROTOCOL_BIN}/transfer \
      '${receipt_file}' '$(abspath $(${n}_root))' '${receipt_destdir}' \
      '${stage}/$n/' ${rsync_flags} $1 --exclude='.*';${nl}))
endef

# Vendored symlinks are dereferenced so the installed manifest remains a set of
# ordinary files with independently comparable content.
define transfer_vendor
$(foreach n,${namespaces},\
  $(if $(wildcard ${vendor}/$n/.),\
    RSYNC='${RSYNC}' DRY_RUN='$1' ${PROTOCOL_BIN}/transfer \
      '${receipt_file}' '$(abspath $(${n}_root))' '${receipt_destdir}' \
      '${vendor}/$n/' ${rsync_flags} --copy-links $1 --exclude='.*';${nl}))
endef

transfer = $(call transfer_stage,$1) $(call transfer_vendor,$1)

.PHONY: preview #> Stage, then report files install would create or overwrite
preview: stage check-install-tools
	$(call transfer,--dry-run)
	$(foreach l,${effective_links},\
	    DRY_RUN=1 ${PROTOCOL_BIN}/ensure-link.sh \
	      '$(call installed_of,$l)' '${DESTDIR}$(call link_of,$l)';${nl})

.PHONY: install #> Stage and install every declared destination namespace
install: stage check-install-tools
	$(if ${DRY_RUN},:,umask 077; mkdir -p '$(dir ${receipt_file})'; : >> '${receipt_file}')
	$(call transfer,$(if ${DRY_RUN},--dry-run))
	$(foreach l,${effective_links},\
	    DRY_RUN='${DRY_RUN}' ${PROTOCOL_BIN}/ensure-link.sh \
	      '$(call installed_of,$l)' '${DESTDIR}$(call link_of,$l)';${nl})

# Uninstall uses installation history, never rebuilding the current declaration.
.PHONY: before-uninstall remove-installed after-uninstall
before-uninstall: check-uninstall-tools

remove-installed: before-uninstall
	MD5SUM='${MD5SUM}' DRY_RUN='${DRY_RUN}' ${PROTOCOL_BIN}/remove-receipt \
	  '${receipt_file}' '${receipt_destdir}'
	$(foreach l,${effective_links},\
	  DRY_RUN='${DRY_RUN}' ${PROTOCOL_BIN}/remove-link.sh \
	    '$(call installed_of,$l)' '${DESTDIR}$(call link_of,$l)';${nl})

after-uninstall: remove-installed

.PHONY: uninstall #> Remove links still ours and files matching their latest receipt MD5
uninstall: after-uninstall

# Interface -------------------------------------------------------------------

.PHONY: help #> Show this help message
help:
	${PROTOCOL_BIN}/help ${MAKEFILE_LIST}

.PHONY: show #> Show resolved variables and manifest paths
show:
	printf 'Environment:\n'
	$(foreach v,HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME XDG_RUNTIME_DIR BIN_DIR,\
	  printf '  %-20s %s\n' '$v' '${$v}';${nl})
	printf '  %-20s %s\n' 'DESTDIR' '${DESTDIR}'
	printf '  %-20s %s\n' 'RECEIPT' '${receipt_file}'
	$(foreach v,${show_vars},\
	  printf '  %-20s %s\n' '$v' '${$v}';${nl})
	$(foreach v,${tools},\
	  printf '  %-20s %s\n' '$v' '$(if ${$v},${$v},(MISSING))';${nl})
	$(foreach v,${required_inputs},\
	  printf '  %-20s %s\n' '$v' '$(if ${$v},${$v},(MISSING))';${nl})
	printf '\nManifest:\n'
	$(foreach f,${files},\
	  printf '  file  %-6s %s\n' '$(call mode_of,$f)' '$(call installed_of,$f)';${nl})
	$(foreach l,${effective_links},\
	  printf '  link         %s -> %s\n' '$(call link_of,$l)' \
	    '$(call installed_of,$l)';${nl})

# Stable tab-separated records for the collection driver. Unlike show, every
# manifest/link record has fixed fields and inspect never stages or mutates.
.PHONY: inspect #> Emit machine-readable effective manifest records
inspect:
	$(foreach f,${files},\
	  printf 'file\t%s\t%s\t%s\t%s\n' '$(call mode_of,$f)' \
	    '$(call manifest_of,$f)' '$f' '$(call installed_of,$f)';${nl})
	$(foreach l,${effective_links},\
	  printf 'link\t-\t-\t%s\t%s\t%s\n' '$l' '$(call link_of,$l)' \
	    '$(call installed_of,$l)';${nl})

# Compatibility projection for callers predating inspect.
.PHONY: fragment-files
fragment-files:
	$(foreach f,$(filter config/env.d/%.sh,${files}),printf '%s\n' '$(call manifest_of,$f)';${nl})

.PHONY: check #> Stage and run concern-defined checks
check: stage
	:

.PHONY: sync #> Synchronize optional runtime or network state
sync: check-sync-tools

.PHONY: clean #> Remove the staging directory
clean:
	rm -rf '${stage}'
