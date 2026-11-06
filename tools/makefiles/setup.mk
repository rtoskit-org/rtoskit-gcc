include ${PROJECT_ROOT}/tools/makefiles/common.mk

# Nothing to set up: the external sources (crosstool-NG and rtoskit-libc) are downloaded, and checked against
# the digests pinned in compilers/arm-none-eabi, by the build that needs them (arm-none-eabi.mk, and crosstool-NG
# itself for rtoskit-libc). SETUP_TARGETS is left for projects that add host tools.
setup-realclean:
	@:
.PHONY: setup-realclean

setup-tools: ${SETUP_TARGETS}
	@:
.PHONY: setup-tools

setup: setup-tools
	@:
.PHONY: setup
