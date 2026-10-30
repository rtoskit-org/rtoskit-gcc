# This file adds functions to build rtoskit-libc as the system C library
# Copyright (C) 2026 Red Rocket Computing, LLC
# Licensed under the GPL v2 or later. See COPYING in the root of this package
#
# rtoskit-libc builds with its own make build, once per architecture
# (ARCH_CROSS) and build type, through its "make library" goal for parent
# builds. Each GCC multilib is mapped to an ARCH_CROSS by
# CT_LIBC_RTOSKIT_MULTILIB_MAP. Headers are per target triple, so one copy
# serves every multilib.

# The headers are plain files in the source tree; no compiler is needed yet
rtoskit_headers()
{
    CT_DoStep INFO "Installing C library headers"
    CT_DoExecLog ALL mkdir -p "${CT_HEADERS_DIR}"
    CT_DoExecLog ALL cp -a "${CT_SRC_DIR}/rtoskit/include/." "${CT_HEADERS_DIR}"
    CT_EndStep
}

# Print the ARCH_CROSS the map gives a multilib directory
rtoskit_arch_for()
{
    local multi_dir="${1}"

    sed -e 's/#.*//' "${CT_LIBC_RTOSKIT_MULTILIB_MAP}" | \
        awk -v dir="${multi_dir}" '$1 == dir { print $2; exit }'
}

# Run the rtoskit-libc build. The ct-ng build runs under make, and the parent
# build exports its own directory variables, so neither may leak in.
rtoskit_make()
{
    CT_DoExecLog ALL env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL -u MAKEOVERRIDES \
        -u BUILD_ROOT -u INSTALL_ROOT -u SOURCE_DIR -u BUILD_PATH -u SUBDIRS \
        -u CPPFLAGS -u CFLAGS -u LDFLAGS \
        make -C "${CT_SRC_DIR}/rtoskit" ${CT_JOBSFLAGS} "$@" library
}

rtoskit_main()
{
    local cross_compile build_dir stage_dir
    local -a multilibs
    local multilib multi_dir arch build_type first lib_dir
    local -A built

    CT_DoStep INFO "Installing C library"

    CT_TestOrAbort "CT_LIBC_RTOSKIT_MULTILIB_MAP is not set" -n "${CT_LIBC_RTOSKIT_MULTILIB_MAP}"
    CT_TestOrAbort "No multilib map ${CT_LIBC_RTOSKIT_MULTILIB_MAP}" -f "${CT_LIBC_RTOSKIT_MULTILIB_MAP}"

    # The core pass compiler, with the target binutils next to it
    cross_compile="$(dirname "$(command -v "${CT_TARGET}-${CT_CC}")")/${CT_TARGET}-"
    CT_TestOrAbort "No core compiler ${cross_compile}${CT_CC}" -x "${cross_compile}${CT_CC}"
    CT_TestOrAbort "No target archiver ${cross_compile}ar" -x "${cross_compile}ar"

    build_dir="${CT_BUILD_DIR}/build-libc"
    stage_dir="${CT_BUILD_DIR}/build-libc-stage"

    # Build every architecture the multilibs need, once per build type
    multilibs=( $("${CT_TARGET}-${CT_CC}" -print-multi-lib) )
    for multilib in "${multilibs[@]}"; do
        multi_dir="${multilib%%;*}"
        arch="$(rtoskit_arch_for "${multi_dir}")"
        CT_TestOrAbort "Multilib ${multi_dir} has no ARCH_CROSS in ${CT_LIBC_RTOSKIT_MULTILIB_MAP}" -n "${arch}"
        [ -n "${built[${arch}]}" ] && continue
        for build_type in ${CT_LIBC_RTOSKIT_BUILD_TYPES}; do
            CT_DoLog EXTRA "Building C library for ${arch} (${build_type})"
            rtoskit_make \
                PROJECT_ROOT="${CT_SRC_DIR}/rtoskit" \
                TOOLS_ROOT="${CT_SRC_DIR}/rtoskit/tools" \
                OUTPUT_ROOT="${build_dir}" \
                PREFIX="${stage_dir}" \
                ARCH_CROSS="${arch}" \
                BUILD_TYPE="${build_type}" \
                CROSS_COMPILE="${cross_compile}"
            # Headers are per triple: every build must install the same ones
            if ! diff -r "${CT_SRC_DIR}/rtoskit/include" "${stage_dir}/${arch}/${build_type}/include" >/dev/null; then
                CT_Abort "rtoskit-libc ${arch} ${build_type} installed headers that differ from the source tree"
            fi
        done
        built[${arch}]=y
    done

    # Install each multilib's archives: the first build type in lib/<multidir>,
    # the others in lib/<multidir>/<build type>
    for multilib in "${multilibs[@]}"; do
        multi_dir="${multilib%%;*}"
        arch="$(rtoskit_arch_for "${multi_dir}")"
        first=y
        for build_type in ${CT_LIBC_RTOSKIT_BUILD_TYPES}; do
            lib_dir="${CT_SYSROOT_DIR}/lib/${multi_dir}"
            [ "${first}" = "y" ] || lib_dir="${lib_dir}/${build_type}"
            first=n
            CT_DoLog EXTRA "Installing ${arch} (${build_type}) into lib/${multi_dir#.}"
            CT_DoExecLog ALL mkdir -p "${lib_dir}"
            CT_DoExecLog ALL install -m 644 "${stage_dir}/${arch}/${build_type}/lib/"*.a "${lib_dir}"
        done
    done

    CT_EndStep
}

# The spec files and the Linux test port's linker script fragment. @GCC_VERSION@ in a spec file becomes the GCC
# version: a spec cannot build a libstdc++ include path from %(version), which ends in a space
rtoskit_post_cc()
{
    local spec

    CT_DoStep INFO "Installing C library spec files"
    for spec in ${CT_LIBC_RTOSKIT_SPECS}; do
        CT_DoExecLog ALL install -m 644 "${spec}" "${CT_SYSROOT_DIR}/lib/"
        CT_DoExecLog ALL sed -i -e "s|@GCC_VERSION@|${CT_GCC_VERSION}|g" "${CT_SYSROOT_DIR}/lib/${spec##*/}"
    done
    if [ -f "${CT_SRC_DIR}/rtoskit/port/linux/arm/headers.ld" ]; then
        CT_DoExecLog ALL install -m 644 "${CT_SRC_DIR}/rtoskit/port/linux/arm/headers.ld" \
            "${CT_SYSROOT_DIR}/lib/rtos-linux-headers.ld"
    fi
    CT_EndStep
}
