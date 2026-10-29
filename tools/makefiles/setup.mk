include ${PROJECT_ROOT}/tools/makefiles/common.mk

# The external sources (crosstool-ng, rtoskit-libc) are git submodules: initialise them, and
# update them again whenever a recorded submodule commit changes (a checkout, pull or bump)
SUBMODULES_STAMP := ${OUTPUT_ROOT}/.submodules
SUBMODULES_STATUS := $(shell git -C ${PROJECT_ROOT} ls-tree HEAD external/ 2>/dev/null; git -C ${PROJECT_ROOT} diff --cached --submodule=short external/ 2>/dev/null)

${SUBMODULES_STAMP}: ${PROJECT_ROOT}/.gitmodules FORCE
	+[ -d $(@D) ] || mkdir -p $(@D)
	if [ ! -f $@ ] || [ "$$(cat $@)" != '$(strip ${SUBMODULES_STATUS})' ] || git -C ${PROJECT_ROOT} submodule status | grep -q '^-'; then \
		echo "UPDATING submodules"; \
		git -C ${PROJECT_ROOT} submodule update --init && echo '$(strip ${SUBMODULES_STATUS})' > $@; \
	fi

FORCE:
.PHONY: FORCE

SETUP_TARGETS += ${SUBMODULES_STAMP}

setup-realclean:
	@:
.PHONY: setup-realclean

setup-tools: ${SETUP_TARGETS}
	@:
.PHONY: setup-tools

setup: setup-tools
	@:
.PHONY: setup
