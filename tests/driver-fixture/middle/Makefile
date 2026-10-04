include ${HOMESTEAD_MK}

REQUIRED_TOOL ?= /bin/true
install_tools += REQUIRED_TOOL

.PHONY: test
test:
	$(if ${FAIL_TEST},false,:)
