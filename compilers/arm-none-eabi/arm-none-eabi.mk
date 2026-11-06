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

# crosstool-NG's progress bar redraws one line with a spinner: useful on a terminal, noise in a log. By default
# it is on only when stderr is a terminal; PROGRESS_BAR=y or n overrides that.
PROGRESS_BAR ?= $(if $(shell [ -t 2 ] && echo y),y,n)
ifeq (${PROGRESS_BAR},n)
PROGRESS_LINE := \# CT_LOG_PROGRESS_BAR is not set
else
PROGRESS_LINE := CT_LOG_PROGRESS_BAR=y
endif

DOWNLOADS := ${PROJECT_ROOT}/downloads

# rtoskit-libc's build needs GNU make 4.4 or newer (.NOTINTERMEDIATE)
ifeq ($(filter notintermediate,${.FEATURES}),)
$(error GNU make 4.4 or newer is required to build rtoskit-libc (this is ${MAKE_VERSION}))
endif

# crosstool-NG is downloaded at the commit CROSSTOOL_NG_REV and checked against CROSSTOOL_NG_SHA256 (versions.inc).
# rtoskit-libc is crosstool-NG's own download: the package overlay below names the release and its digests
ifeq ($(wildcard ${SOURCE_DIR}/crosstool-ng/packages/rtoskit/${RTOSKIT_LIBC_VERSION}/chksum),)
$(error RTOSKIT_LIBC_VERSION ${RTOSKIT_LIBC_VERSION} has no package in ${SOURCE_DIR}/crosstool-ng/packages/rtoskit: run tools/scripts/gcc-releases bump-libc ${RTOSKIT_LIBC_VERSION})
endif
CT_NG_TARBALL := ${DOWNLOADS}/crosstool-ng-${CROSSTOOL_NG_REV}.tar.gz

# crosstool-NG is built from the downloaded source with our additions (the rtoskit libc backend and
# package) laid over it
CT_NG_ROOT := ${CURDIR}/crosstool-ng
CT_NG := ${CT_NG_ROOT}/ct-ng
CT_NG_REMOVE := ${SOURCE_DIR}/crosstool-ng.remove
CT_NG_OVERLAY := $(shell find ${SOURCE_DIR}/crosstool-ng -type f) $(wildcard ${CT_NG_REMOVE})

# GCC reads a custom multilib fragment only from gcc/config/arm, so t-rtoskit goes in as a
# local patch common to every GCC version
PATCH_DIR := ${CURDIR}/patches
T_RTOSKIT_PATCH := ${PATCH_DIR}/gcc/0001-arm-add-t-rtoskit-multilib-fragment.patch

# The GCC patches kept in the source tree, applied to every version
GCC_PATCHES := $(patsubst ${SOURCE_DIR}/gcc-patches/%,${PATCH_DIR}/gcc/%,$(wildcard ${SOURCE_DIR}/gcc-patches/*.patch))

# A change of the crosstool-NG commit or of the rtoskit-libc release rebuilds what depends on it
TOOLCHAIN_INPUTS := ${SOURCE_DIR}/arm-none-eabi.defconfig.in ${SOURCE_DIR}/versions.inc ${T_RTOSKIT_PATCH} ${GCC_PATCHES} ${CT_NG} ${CURDIR}/rtoskit-libc.rev \
	${SOURCE_DIR}/rtoskit/multilib.map ${SOURCE_DIR}/rtoskit/rtoskit.specs ${SOURCE_DIR}/rtoskit/rtoskit-linux.specs

toolchain-name = gcc-arm-none-eabi-$(subst .,-,${1})
TOOLCHAINS := $(foreach version,${GCC_VERSIONS},${PREFIX}/$(call toolchain-name,${version}).tar.xz)

# Every crosstool-NG build already uses all the cores
.NOTPARALLEL:

all: ${TOOLCHAINS}
	@

clean:
	@

${CURDIR}/crosstool-ng.rev: FORCE
	[ -f $@ ] && [ "$$(cat $@)" = "${CROSSTOOL_NG_REV}" ] || echo "${CROSSTOOL_NG_REV}" > $@

${CURDIR}/rtoskit-libc.rev: FORCE
	[ -f $@ ] && [ "$$(cat $@)" = "${RTOSKIT_LIBC_VERSION}" ] || echo "${RTOSKIT_LIBC_VERSION}" > $@

FORCE:
.PHONY: FORCE

# The commit's source archive, from GitHub, checked against the pinned digest
${CT_NG_TARBALL}:
	@echo "DOWNLOADING crosstool-NG ${CROSSTOOL_NG_REV}"
	mkdir -p $(@D)
	curl -fsSL --retry 3 -o $@.part https://github.com/crosstool-ng/crosstool-ng/archive/${CROSSTOOL_NG_REV}.tar.gz
	echo "${CROSSTOOL_NG_SHA256}  $@.part" | sha256sum -c --status - || { echo "crosstool-NG ${CROSSTOOL_NG_REV}: the download does not match CROSSTOOL_NG_SHA256 ($$(sha256sum $@.part | cut -d' ' -f1))" >&2; $(RM) $@.part; exit 1; }
	mv $@.part $@

${CT_NG}: ${CT_NG_TARBALL} ${CT_NG_OVERLAY} ${CURDIR}/crosstool-ng.rev
	@echo "BUILDING crosstool-NG ${CROSSTOOL_NG_REV}"
	$(RM) -r ${CT_NG_ROOT}
	mkdir -p ${CT_NG_ROOT}
	tar -xzf ${CT_NG_TARBALL} -C ${CT_NG_ROOT} --strip-components=1
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

${PATCH_DIR}/gcc/%.patch: ${SOURCE_DIR}/gcc-patches/%.patch
	mkdir -p $(@D)
	cp ${<} ${@}

# One crosstool-NG work directory per GCC version: gcc-<version>/
${CURDIR}/gcc-%/.config: ${TOOLCHAIN_INPUTS}
	@echo "CONFIGURING GCC $*"
	mkdir -p $(@D) ${PROJECT_ROOT}/downloads
	sed -e 's|@GCC_MAJOR@|$(firstword $(subst ., ,$*))|g' \
	    -e 's|@SOURCE_DIR@|${SOURCE_DIR}|g' \
	    -e 's|@PATCH_DIR@|${PATCH_DIR}|g' \
	    -e 's|@PROJECT_ROOT@|${PROJECT_ROOT}|g' \
	    -e 's|@RTOSKIT_LIBC_VERSION_ID@|$(subst .,_,${RTOSKIT_LIBC_VERSION})|g' \
	    -e 's|@BUILD_MANUALS@|${MANUALS_LINE}|g' \
	    -e 's|@PROGRESS_BAR@|${PROGRESS_LINE}|g' \
	    ${SOURCE_DIR}/arm-none-eabi.defconfig.in > $(@D)/defconfig
	cd $(@D) && ${CT_NG} defconfig DEFCONFIG=$(@D)/defconfig
	grep -q '^CT_GCC_VERSION="$*"$$' $@ || { echo "crosstool-NG ${CROSSTOOL_NG_REV} has no GCC $* (it selected $$(grep '^CT_GCC_VERSION=' $@)); see tools/scripts/gcc-releases" >&2; exit 1; }

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
