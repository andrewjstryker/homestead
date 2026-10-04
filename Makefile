.DEFAULT_GOAL := help
SHELL := /bin/sh

.PHONY: help test lint version
help:
	@printf '%s\n' 'test  Run isolated lifecycle and driver tests' 'lint  Check shell syntax and ShellCheck warnings'

BATS ?= bats

# Override TESTS to run one file; BATS_FLAGS accepts filters and runner options.
TESTS ?= tests
BATS_FLAGS ?=
test:
	@$(BATS) $(BATS_FLAGS) $(TESTS)

lint:
	@for script in home bin/*; do sh -n "$$script" || exit; done
	@bash -n tests/test_helper.bash
	@shellcheck -x -S warning home bin/* tests/*.bats tests/*.bash

version:
	@cat VERSION
