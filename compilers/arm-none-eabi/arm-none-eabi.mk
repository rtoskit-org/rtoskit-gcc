#
# Copyright (C) 2023 Red Rocket Computing, LLC
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# arm-none-eabi.mk
#
# Created on: Mar 5, 2023
#     Author: Stephen Street (stephen@redrocketcomputing.com)
#
# Builds one arm-none-eabi toolchain with rtoskit-libc for every GCC release in
# GCC_VERSIONS (versions.inc) with crosstool-NG, and packages each one as
# ${PREFIX}/gcc-arm-none-eabi-<major>-<minor>-<patch>.tar.xz.
#

ifeq ($(findstring ${BUILD_ROOT},${CURDIR}),)
include ${TOOLS_ROOT}/makefiles/target.mk
else

include ${TOOLS_ROOT}/makefiles/common.mk
include ${SOURCE_DIR}/versions.inc

# BUILD_MANUALS=n skips the GCC and binutils PDF and HTML manuals: faster, and no TeX needed
BUILD_MANUALS ?= y
ifeq (${BUILD_MANUALS},n)
MANUALS_LINE := \# CT_BUILD_MANUALS is not set
else
MANUALS_LINE := CT_BUILD_MANUALS=y
endif

CROSSTOOL_NG_SOURCE := ${PROJECT_ROOT}/external/crosstool-ng
RTOSKIT_LIBC_SOURCE := ${PROJECT_ROOT}/external/rtoskit-libc

# rtoskit-libc's build needs GNU make 4.4 or newer (.NOTINTERMEDIATE)
ifeq ($(filter notintermediate,${.FEATURES}),)
$(error GNU make 4.4 or newer is required to build rtoskit-libc (this is ${MAKE_VERSION}))
endif

ifeq ($(wildcard ${CROSSTOOL_NG_SOURCE}/bootstrap),)
$(error ${CROSSTOOL_NG_SOURCE} is empty: run "make setup" or "git submodule update --init")
endif
ifeq ($(wildcard ${RTOSKIT_LIBC_SOURCE}/Makefile),)
$(error ${RTOSKIT_LIBC_SOURCE} is empty: run "make setup" or "git submodule update --init")
endif

# crosstool-NG is built from a copy of the submodule with our additions (the rtoskit libc
# backend) laid over it, so the submodule itself stays clean
CT_NG_ROOT := ${CURDIR}/crosstool-ng
CT_NG := ${CT_NG_ROOT}/ct-ng
CT_NG_REMOVE := ${SOURCE_DIR}/crosstool-ng.remove
CT_NG_OVERLAY := $(shell find ${SOURCE_DIR}/crosstool-ng -type f) $(wildcard ${CT_NG_REMOVE})

# GCC reads a custom multilib fragment only from gcc/config/arm, so t-rtoskit goes in as a
# local patch common to every GCC version
PATCH_DIR := ${CURDIR}/patches
T_RTOSKIT_PATCH := ${PATCH_DIR}/gcc/0001-arm-add-t-rtoskit-multilib-fragment.patch

# A change of either submodule's commit rebuilds what depends on it
REVISIONS := ${CURDIR}/crosstool-ng.rev ${CURDIR}/rtoskit-libc.rev

TOOLCHAIN_INPUTS := ${SOURCE_DIR}/arm-none-eabi.defconfig.in ${T_RTOSKIT_PATCH} ${CT_NG} ${CURDIR}/rtoskit-libc.rev \
	${SOURCE_DIR}/rtoskit/multilib.map ${SOURCE_DIR}/rtoskit/rtoskit.specs ${SOURCE_DIR}/rtoskit/rtoskit-linux.specs

toolchain-name = gcc-arm-none-eabi-$(subst .,-,${1})
TOOLCHAINS := $(foreach version,${GCC_VERSIONS},${PREFIX}/$(call toolchain-name,${version}).tar.xz)

# Every crosstool-NG build already uses all the cores
.NOTPARALLEL:

all: ${TOOLCHAINS}
	@

clean:
	@

${CURDIR}/%.rev: FORCE
	rev="$$(git -C ${PROJECT_ROOT}/external/$* rev-parse HEAD)"; \
	[ -f $@ ] && [ "$$(cat $@)" = "$$rev" ] || echo "$$rev" > $@

FORCE:
.PHONY: FORCE

${CT_NG}: ${CT_NG_OVERLAY} ${CURDIR}/crosstool-ng.rev
	@echo "BUILDING crosstool-NG $$(cat ${CURDIR}/crosstool-ng.rev)"
	$(RM) -r ${CT_NG_ROOT}
	rsync -a --exclude .git ${CROSSTOOL_NG_SOURCE}/ ${CT_NG_ROOT}/
	rsync -a ${SOURCE_DIR}/crosstool-ng/ ${CT_NG_ROOT}/
	if [ -f ${CT_NG_REMOVE} ]; then \
		sed -e 's/\#.*//' ${CT_NG_REMOVE} | while read -r path; do [ -z "$$path" ] || $(RM) -r "${CT_NG_ROOT}/$$path"; done; \
	fi
	cd ${CT_NG_ROOT} && ./bootstrap
	cd ${CT_NG_ROOT} && ./configure --enable-local
	+cd ${CT_NG_ROOT} && $(MAKE)

${T_RTOSKIT_PATCH}: ${SOURCE_DIR}/t-rtoskit
	@echo "GENERATING ${@}"
	mkdir -p $(@D)
	{ \
		echo "Add the rtoskit-libc multilib fragment (--with-multilib-list=@t-rtoskit)"; \
		echo; \
		echo "--- /dev/null"; \
		echo "+++ b/gcc/config/arm/t-rtoskit"; \
		echo "@@ -0,0 +1,$$(wc -l < ${<}) @@"; \
		sed 's/^/+/' ${<}; \
	} > ${@}

# One crosstool-NG work directory per GCC version: gcc-<version>/
${CURDIR}/gcc-%/.config: ${TOOLCHAIN_INPUTS}
	@echo "CONFIGURING GCC $*"
	mkdir -p $(@D) ${PROJECT_ROOT}/downloads
	sed -e 's|@GCC_MAJOR@|$(firstword $(subst ., ,$*))|g' \
	    -e 's|@SOURCE_DIR@|${SOURCE_DIR}|g' \
	    -e 's|@PATCH_DIR@|${PATCH_DIR}|g' \
	    -e 's|@PROJECT_ROOT@|${PROJECT_ROOT}|g' \
	    -e 's|@BUILD_MANUALS@|${MANUALS_LINE}|g' \
	    ${SOURCE_DIR}/arm-none-eabi.defconfig.in > $(@D)/defconfig
	cd $(@D) && ${CT_NG} defconfig DEFCONFIG=$(@D)/defconfig
	grep -q '^CT_GCC_VERSION="$*"$$' $@ || { echo "crosstool-NG $$(cat ${CURDIR}/crosstool-ng.rev) has no GCC $* (it selected $$(grep '^CT_GCC_VERSION=' $@)); see tools/scripts/gcc-releases" >&2; exit 1; }

${CURDIR}/gcc-%/.built: ${CURDIR}/gcc-%/.config
	@echo "BUILDING $(call toolchain-name,$*)"
	cd $(@D) && TOOLCHAIN_NAME=$(call toolchain-name,$*) ${CT_NG} build
	mv $(@D)/$(call toolchain-name,$*)/build.log.bz2 $(@D)/
	touch $@

.SECONDEXPANSION:
${PREFIX}/gcc-arm-none-eabi-%.tar.xz: ${CURDIR}/gcc-$$(subst -,.,$$*)/.built
	@echo "PACKAGING $(@F)"
	mkdir -p $(@D)
	tar -C $(<D) -c -I 'xz -9 -T0' -f $@ $(basename $(basename $(@F)))

endif
