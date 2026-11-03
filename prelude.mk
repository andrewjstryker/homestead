# prelude.mk -- where a Homestead module's inputs come from
#
# Include this before anything else in the module Makefile, then set module
# defaults with ?=, then include homestead.mk. Every input then has exactly one
# source, in this order:
#
#   1. a Make command-line assignment (development and tests);
#   2. the environment table named by ENV_FILE;
#   3. a ?= default: the roots below, or the module's own.
#
# The process environment is not a source. Installed modules export their
# values into every shell through env.d fragments, so an inherited value is
# usually the previous installation talking. Honoring it would let a stale
# export beat a changed table or default, and the build would stamp it in again.

ifndef homestead_prelude
homestead_prelude := $(lastword ${MAKEFILE_LIST})
homestead_dir := $(patsubst %/,%,$(dir ${homestead_prelude}))

# Inherited values ----------------------------------------------------------

# Process plumbing passes; so does Make's own state. A Make started beneath a
# recipe of one that already applied this rule keeps what that parent passed
# down, so the rule marks the environment it hands its recipes. MAKELEVEL is
# not enough: any Make, prelude or not, raises it.
homestead_plumbing := $(subst *,%,$(file < ${homestead_dir}/plumbing))
homestead_make_state := MAKEFLAGS MFLAGS GNUMAKEFLAGS MAKELEVEL MAKE_TERMOUT MAKE_TERMERR

ifneq ($(HOMESTEAD_RESOLVED)$(origin HOMESTEAD_RESOLVED),1environment)
$(foreach v,${.VARIABLES},$(if $(filter environment%,$(origin $v)),\
  $(if $(filter ${homestead_plumbing} ${homestead_make_state},$v),,$(eval undefine $v))))
endif
export HOMESTEAD_RESOLVED := 1

# The environment table -------------------------------------------------------

# A collection driver names its table; a standalone module reads its own .env.
# An explicitly named table must exist, the default is optional, and an empty
# name means no table. The file is data: NAME=value lines, validated first.
ENV_FILE ?= .env
homestead_table_vars :=
homestead_hash := \#
define homestead_nl


endef
ifneq ($(strip ${ENV_FILE}),)
homestead_table := $(shell '${homestead_dir}/bin/env-table' '${ENV_FILE}' \
  $(if $(filter file,$(origin ENV_FILE)),optional) || echo '!invalid')
ifneq ($(filter !invalid,${homestead_table}),)
$(error invalid environment table: ${ENV_FILE})
endif
$(eval $(subst ${homestead_hash},${homestead_nl},${homestead_table}))
endif

# Recipes see table values, as they see any other input.
export ${homestead_table_vars}

# The build floor -------------------------------------------------------------

# Locations every module may assume while it builds, with or without a
# collection. A collection's runtime floor (its first modules) publishes the
# resolved values to shells; it never feeds them back in.
XDG_CONFIG_HOME ?= ${HOME}/.config
XDG_DATA_HOME   ?= ${HOME}/.local/share
XDG_STATE_HOME  ?= ${HOME}/.local/state
XDG_CACHE_HOME  ?= ${HOME}/.cache
BIN_DIR         ?= ${HOME}/.local/bin
LIBEXEC_DIR     ?= ${HOME}/.local/libexec

homestead_root_vars := \
  XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME BIN_DIR LIBEXEC_DIR

# An empty root would write beneath /; so would an empty HOME behind a default.
require_nonempty = $(if $(strip $($1)),,$(error $1 must not be empty))
$(foreach v,HOME ${homestead_root_vars},$(call require_nonempty,$v))
endif
