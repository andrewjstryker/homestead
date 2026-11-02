include ../_homestead/prelude.mk
include ../_homestead/homestead.mk

.PHONY: maybe-fail-install optional-sync
maybe-fail-install:
	$(if ${FAIL_INSTALL},false,:)

optional-sync:
	printf 'runtime-fail-sync\n' >> '${SYNC_LOG}'

install: maybe-fail-install
sync: optional-sync
