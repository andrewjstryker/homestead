# table.mk -- report the environment as every module resolves it
#
# The driver asks Make rather than parsing the table itself, so the collection
# and its modules cannot read one file two ways. Output is NAME=value lines:
# the shared roots, then each table entry.

include $(dir $(lastword ${MAKEFILE_LIST}))prelude.mk

.PHONY: table
table:
	$(foreach v,${homestead_root_vars} $(filter-out ${homestead_root_vars},${homestead_table_vars}),$(info $v=$($v)))@:
