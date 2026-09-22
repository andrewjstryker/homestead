.DEFAULT_GOAL := help
SHELL := /bin/sh

.PHONY: help test lint
help:
	@printf '%s\n' 'test  Run isolated lifecycle and driver tests' 'lint  Check shell syntax and ShellCheck warnings'

test:
	@sh tests/staging.sh
	@sh tests/driver.sh

lint:
	@for script in home bin/* tests/*.sh; do sh -n "$$script" || exit; done
	@shellcheck -S warning home bin/* tests/*.sh
