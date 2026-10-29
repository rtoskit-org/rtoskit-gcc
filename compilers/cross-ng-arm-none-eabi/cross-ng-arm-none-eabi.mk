#
# Copyright (C) 2023 Red Rocket Computing, LLC
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# cross-ng-arm-none-eabi.mk
#
# Created on: Mar 5, 2023
#     Author: Stephen Street (stephen@redrocketcomputing.com)
#

ifeq ($(findstring ${BUILD_ROOT},${CURDIR}),)
include ${TOOLS_ROOT}/makefiles/target.mk
else

include ${TOOLS_ROOT}/makefiles/common.mk

export TOOLCHAIN_NAME := gcc-arm-none-eabi-$(shell grep "CT_GCC_VERSION=" ${SOURCE_DIR}/arm-none-eabi.conf | cut -d \" -f 2 | sed 's/\./-/g')
export CURDIR := ${CURDIR}

all: ${PREFIX}/${TOOLCHAIN_NAME}.tar.xz
	@

clean:
	@

${CURDIR}/crosstool-ng/bootstrap:
	@echo CLONING https://github.com/crosstool-ng/crosstool-ng
	git clone https://github.com/crosstool-ng/crosstool-ng
#	@echo PATCHING picolibc
#	$(INSTALL) -m 660 ${SOURCE_DIR}/0000-Revert-include-Remove-BSD-threads.h-file.patch ${CURDIR}/crosstool-ng/packages/picolibc/1.8.10/0000-Revert-include-Remove-BSD-threads.h-file.patch
	
${CURDIR}/crosstool-ng/configure: ${CURDIR}/crosstool-ng/bootstrap
	@echo BOOTSTRAPING ${@}
	cd ${CURDIR}/crosstool-ng && ./bootstrap

${CURDIR}/crosstool-ng/Makefile: ${CURDIR}/crosstool-ng/configure
	@echo CONFIGURING ${@}
	cd ${CURDIR}/crosstool-ng && ./configure --enable-local

${CURDIR}/crosstool-ng/ct-ng: ${CURDIR}/crosstool-ng/Makefile
	@echo BUILDING ${@}
	cd ${CURDIR}/crosstool-ng && make

${CURDIR}/.config: ${SOURCE_DIR}/arm-none-eabi.conf
	@echo INSTALLING ${<} ${@}
	$(INSTALL) -m 660 ${<} ${@}

${CURDIR}/${TOOLCHAIN_NAME}/bin/arm-none-eabi-ct-ng.config: ${CURDIR}/.config ${CURDIR}/crosstool-ng/ct-ng
	@echo BUILDING ${TOOLCHAIN_NAME}
	+[ -d $@ ] || mkdir -p ${PROJECT_ROOT}/downloads
	${CURDIR}/crosstool-ng/ct-ng build
#	$(INSTALL) -m 660 ${SOURCE_DIR}/picolibc.specs ${CURDIR}/${TOOLCHAIN_NAME}/arm-none-eabi/lib/picolibc.specs
#	$(INSTALL) -m 660 ${SOURCE_DIR}/picolibcpp.specs ${CURDIR}/${TOOLCHAIN_NAME}/arm-none-eabi/lib/picolibcpp.specs
	mv ${CURDIR}/${TOOLCHAIN_NAME}/build.log.bz2 ${CURDIR}

${PREFIX}/${TOOLCHAIN_NAME}.tar.xz: ${CURDIR}/${TOOLCHAIN_NAME}/bin/arm-none-eabi-ct-ng.config
	@echo PACKAGING ${TOOLCHAIN_NAME}
	+[ -d $@ ] || mkdir -p ${PREFIX}
	tar -c -I 'xz -9 -T0' -f ${PREFIX}/${TOOLCHAIN_NAME}.tar.xz ${TOOLCHAIN_NAME}

endif
