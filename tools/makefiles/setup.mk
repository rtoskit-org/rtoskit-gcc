include ${PROJECT_ROOT}/tools/makefiles/common.mk

setup-realclean:
	@:
.PHONY: setup-realclean

setup-tools: ${SETUP_TARGETS}
	@:
.PHONY: setup-tools

setup: setup-tools
	@:
.PHONY: setup
