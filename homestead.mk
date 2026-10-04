# homestead.mk -- shared Homestead module build and lifecycle rules
#
# src is the first-party declaration. Every unclaimed non-hidden path below it
# has the same relative path below stage, except that a final .m4 suffix is
# removed. Modules claim inputs and publish outputs for other transformations.
# vendor is the third-party declaration: mapped namespace directories below it
# are installed directly and are never copied into stage. Dot-prefixed paths in
# either tree, and unmapped vendor directories such as vendor/build, are private.

homestead_mk := $(lastword ${MAKEFILE_LIST})
homestead_bin := $(patsubst %/,%,$(dir ${homestead_mk}))/bin

ifeq ($(origin SHELL),default)
SHELL := /bin/sh
endif
ifeq ($(origin .SHELLFLAGS),default)
.SHELLFLAGS := -eu -c
endif
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:
.SILENT:

# Public operations in workflow order; internal gates are not user commands.
.PHONY: help #> Show this help message
.PHONY: show #> Show resolved variables and manifest paths
.PHONY: check #> Run full preflight without staging or installing
.PHONY: stage #> Prune and incrementally realize the complete staged manifest
.PHONY: preview #> Stage, then report files install would create or overwrite
.PHONY: install #> Stage and install every declared destination namespace
.PHONY: sync #> Synchronize optional runtime or network state
.PHONY: uninstall #> Remove links still ours and files matching their latest receipt MD5
.PHONY: clean #> Remove the staging directory

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
receipt_destdir := $(if ${DESTDIR},$(abspath ${DESTDIR}))
receipt_dir := ${receipt_destdir}${CURDIR}/.homestead
receipt_file := ${receipt_dir}/receipt

DESTDIR ?=

# Tools and caller inputs ------------------------------------------------------

M4    ?= $(shell command -v m4)
RSYNC ?= $(shell command -v rsync)
MD5SUM ?= $(shell command -v md5sum)
m4_vars ?=

# Tool lists contain variable names rather than commands. Wrappers extend the
# phase in which a tool is first required; check diagnoses every phase.
stage_tools   ?=
install_tools ?=
uninstall_tools ?=
sync_tools    ?=
homestead_stage_tools = ${stage_tools} $(if $(strip ${m4_sources}),M4)
homestead_install_tools = ${install_tools} RSYNC
homestead_uninstall_tools = ${uninstall_tools} MD5SUM
tools = $(sort ${homestead_stage_tools} ${homestead_install_tools} ${sync_tools} ${homestead_uninstall_tools})

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
# template variables. m4_flags is reserved for m4 options such as include paths.
m4_context_content = \
  M4=${M4}${nl} \
  m4_flags=${m4_flags}${nl} \
  HOME=${HOME}${nl} \
  $(foreach v,${m4_render_vars},$v=$($v)${nl})

export M4_CONTEXT = ${m4_context_content}
export M4_CONTEXT_FILE = ${m4_context}

# Diagnostics return a marker after reporting an error. Expanding the entire
# list before failing lets full preflight report every phase in one Make graph.
tool_errors = $(if $(call missing_tools,$1),\
  $(warning Missing tools needed to $2: $(call missing_tools,$1))missing)
input_errors = $(if ${missing_inputs},\
  $(warning Missing required inputs needed to stage: ${missing_inputs})missing)
stage_errors = ${declaration_errors} ${input_errors} $(call tool_errors,${homestead_stage_tools},stage)

.PHONY: check-stage-tools check-install-tools check-sync-tools check-uninstall-tools
check-stage-tools:
	$(if $(strip ${stage_errors}),false,:)

check-install-tools:
	$(if $(call tool_errors,${homestead_install_tools},install),false,:)

check-sync-tools:
	$(if $(call tool_errors,${sync_tools},sync),false,:)

check-uninstall-tools:
	$(if $(call tool_errors,${homestead_uninstall_tools},uninstall),false,:)

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
discovered_sources := $(filter-out ${source_excludes},$(call rwildcard,${src}/,*))
sources           := $(filter-out ${claimed_sources},${discovered_sources})
source_dirs      := $(patsubst %/,%,$(call rdirectories,${src}/))
m4_sources       := $(filter %.m4,${sources})
plain_sources    := $(filter-out ${m4_sources},${sources})

staged_files := \
  $(patsubst ${src}/%,${stage}/%,${plain_sources}) \
  $(patsubst ${src}/%.m4,${stage}/%,${m4_sources}) \
  ${claimed_outputs}
staged_dirs := $(patsubst ${src}/%,${stage}/%,${source_dirs})

stage_files := $(patsubst ${stage}/%,%,${staged_files})

# Build directories are real targets. Their timestamps never invalidate files.
# Include output parents in pruning's declaration so pruning cannot remove a
# directory Make has already observed as current.
output_dirs := $(sort $(patsubst %/,%,$(dir ${staged_files})))
build_dirs := $(sort ${staged_dirs} ${output_dirs} $(if ${m4_sources},${stage}/.build))

.PHONY: prune
prune: check-stage-tools
	${homestead_bin}/prune '${stage}' ${staged_dirs} ${output_dirs} ${staged_files}

ifneq ($(strip ${build_dirs}),)
${build_dirs}: | prune
	mkdir -p '$@'
endif

.SECONDEXPANSION:
ifneq ($(strip ${staged_files}),)
$(sort ${staged_files}): | prune $$(@D)
endif

# A reconciled context tracks non-file render inputs without making outputs phony.
m4_context := ${stage}/.build/m4-context
.PHONY: update-m4-context
ifneq ($(strip ${m4_sources}),)
update-m4-context: | ${stage}/.build
	${homestead_bin}/m4-context '${m4_context}'
endif
${m4_context}: update-m4-context ;

${stage}/%: ${src}/%.m4 ${m4_context}
	M4='${M4}' ${homestead_bin}/gen '$@' '$<' ${m4_flags} ${m4_define_args}

${stage}/%: ${src}/%
	cp -p '$<' '$@'

stage: prune ${staged_dirs} ${staged_files}
	${homestead_bin}/validate-stage '${stage}' ${staged_dirs} -- ${staged_files}

# Namespace mapping -----------------------------------------------------------

namespaces := config data state cache bin

# Snapshot vendor discovery once, retaining empty namespace directories for transfer.
vendor_dirs := $(patsubst %/,%,$(wildcard $(addsuffix /,$(addprefix ${vendor}/,${namespaces}))))
vendor_sources := $(if ${vendor_dirs},$(filter-out ${source_excludes},$(shell \
  find $(foreach d,${vendor_dirs},'$d') -name '.*' -prune -o \
    \( -type f -o -type l \) -print)))
vendor_files := $(patsubst ${vendor}/%,%,${vendor_sources})
files := ${stage_files} ${vendor_files}
stage_namespaces := $(foreach n,${namespaces},$(if $(filter $n $n/%,${stage_files} $(patsubst ${stage}/%,%,${staged_dirs})),$n))
vendor_namespaces := $(patsubst ${vendor}/%,%,${vendor_dirs})

config_root_variable := XDG_CONFIG_HOME
data_root_variable := XDG_DATA_HOME
state_root_variable := XDG_STATE_HOME
cache_root_variable := XDG_CACHE_HOME
bin_root_variable := BIN_DIR

namespace_of = $(firstword $(subst /, ,$1))
relative_of  = $(patsubst $(call namespace_of,$1)/%,%,$1)
root_of      = $($($(call namespace_of,$1)_root_variable))
installed_of = $(call root_of,$1)/$(call relative_of,$1)

claimed_files := $(patsubst ${stage}/%,%,${claimed_outputs})
source_of   = $(firstword $(wildcard ${src}/$1 ${src}/$1.m4))
manifest_of = $(if $(filter $1,${vendor_files}),${vendor}/$1,${stage}/$1)
declared_by = $(if $(filter $1,${vendor_files}),${vendor}/$1,$(if $(filter $1,${claimed_files}),${stage}/$1,$(call source_of,$1)))
mode_of     = $(if $(shell test -x '$(call declared_by,$1)' && echo x),0700,0600)

# A link names its manifest path. link_of adapts that path to the legacy place
# the application insists on; modules override it when the default
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

declaration_duplicate_files := $(strip $(call declaration_duplicates,${files}))
declaration_dirs := $(sort $(patsubst ${stage}/%,%,${staged_dirs}) $(foreach f,${files},$(call declaration_parents,$f)))
declaration_conflicts := $(filter ${files},${declaration_dirs})
declaration_errors = \
  $(if ${declaration_duplicate_files},$(warning Duplicate manifest files: ${declaration_duplicate_files})duplicate) \
  $(if ${declaration_conflicts},$(warning Manifest paths declared as both file and directory: ${declaration_conflicts})conflict)

.PHONY: check-declarations
check-declarations:
	$(if $(strip ${declaration_errors}),false,:)

# Transfer --------------------------------------------------------------------

# Content and permissions are authoritative; timestamps are not. This chmod
# removes group/world access without changing the source's owner-executable bit.
rsync_flags := \
  --recursive --checksum --perms --itemize-changes --mkpath \
  --chmod=u+rw,go-rwx

define transfer_stage
$(foreach n,${stage_namespaces},\
    RSYNC='${RSYNC}' DRY_RUN='$1' ${homestead_bin}/transfer \
      '${receipt_file}' '$(abspath $(call root_of,$n))' '${receipt_destdir}' \
      '${stage}/$n/' ${rsync_flags} $1 --exclude='.*';${nl})
endef

# Vendored symlinks are dereferenced so the installed manifest remains a set of
# ordinary files with independently comparable content.
define transfer_vendor
$(foreach n,${vendor_namespaces},\
    RSYNC='${RSYNC}' DRY_RUN='$1' ${homestead_bin}/transfer \
      '${receipt_file}' '$(abspath $(call root_of,$n))' '${receipt_destdir}' \
      '${vendor}/$n/' ${rsync_flags} --copy-links $1 --exclude='.*';${nl})
endef

transfer = $(call transfer_stage,$1) $(call transfer_vendor,$1)

preview: stage check-install-tools
	$(call transfer,--dry-run)
	$(foreach l,${links},\
	    DRY_RUN=1 ${homestead_bin}/ensure-link.sh \
	      '$(call installed_of,$l)' '${DESTDIR}$(call link_of,$l)';${nl})

# Receipt creation is an installation dependency, omitted for dry runs.
ifeq ($(strip ${DRY_RUN}),)
${receipt_dir}: | stage check-install-tools
	umask 077; mkdir -p '$@'
${receipt_file}: | ${receipt_dir}
	umask 077; : >> '$@'
install: | ${receipt_file}
endif

install: stage check-install-tools
	$(call transfer,$(if ${DRY_RUN},--dry-run))
	$(foreach l,${links},\
	    DRY_RUN='${DRY_RUN}' ${homestead_bin}/ensure-link.sh \
	      '$(call installed_of,$l)' '${DESTDIR}$(call link_of,$l)';${nl})

# Uninstall uses installation history, never rebuilding the current declaration.
.PHONY: before-uninstall remove-installed after-uninstall
before-uninstall: check-uninstall-tools

remove-installed: before-uninstall
	MD5SUM='${MD5SUM}' DRY_RUN='${DRY_RUN}' ${homestead_bin}/remove-receipt \
	  '${receipt_file}' '${receipt_destdir}'
	$(foreach l,${links},\
	  DRY_RUN='${DRY_RUN}' ${homestead_bin}/remove-link.sh \
	    '$(call installed_of,$l)' '${DESTDIR}$(call link_of,$l)';${nl})

after-uninstall: remove-installed

uninstall: after-uninstall

# Interface -------------------------------------------------------------------

help:
	${homestead_bin}/help ${MAKEFILE_LIST}

show:
	printf 'Environment:\n'
	$(foreach v,HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME XDG_RUNTIME_DIR BIN_DIR,\
	  printf '  %-20s %s\n' '$v' '${$v}';${nl})
	printf '  %-20s %s\n' 'DESTDIR' '${DESTDIR}'
	printf '  %-20s %s\n' 'receipt' '${receipt_file}'
	$(foreach v,${show_vars},\
	  printf '  %-20s %s\n' '$v' '${$v}';${nl})
	$(foreach v,${tools},\
	  printf '  %-20s %s\n' '$v' '$(if ${$v},${$v},(MISSING))';${nl})
	$(foreach v,${required_inputs},\
	  printf '  %-20s %s\n' '$v' '$(if ${$v},${$v},(MISSING))';${nl})
	printf '\nManifest:\n'
	$(foreach f,${files},\
	  printf '  file  %-6s %s\n' '$(call mode_of,$f)' '$(call installed_of,$f)';${nl})
	$(foreach l,${links},\
	  printf '  link         %s -> %s\n' '$(call link_of,$l)' \
	    '$(call installed_of,$l)';${nl})

# Stable tab-separated records for the collection driver. Unlike show, every
# manifest/link record has fixed fields and inspect never stages or mutates.
.PHONY: inspect
inspect:
	$(foreach f,${files},\
	  printf 'file\t%s\t%s\t%s\t%s\n' '$(call mode_of,$f)' \
	    '$(call manifest_of,$f)' '$f' '$(call installed_of,$f)';${nl})
	$(foreach l,${links},\
	  printf 'link\t-\t-\t%s\t%s\t%s\n' '$l' '$(call link_of,$l)' \
	    '$(call installed_of,$l)';${nl})

# Compatibility projection for callers predating inspect.
.PHONY: fragment-files
fragment-files:
	$(foreach f,$(filter config/env.d/%.sh,${files}),printf '%s\n' '$(call manifest_of,$f)';${nl})

.PHONY: check-prerequisites
check-prerequisites:
	$(if $(strip ${stage_errors} \
	  $(call tool_errors,${homestead_install_tools},install) \
	  $(call tool_errors,${sync_tools},sync) \
	  $(call tool_errors,${homestead_uninstall_tools},uninstall)),false,:)

check: check-prerequisites
	:

sync: check-sync-tools

clean:
	rm -rf '${stage}'
