# The GCC releases built, newest major first: the latest minor release of each of
# the last three majors. Maintained by tools/scripts/gcc-releases (check, update, rotate).
# Override on the command line to build a subset, e.g. make GCC_VERSIONS=16.2.0
GCC_VERSIONS ?= 16.2.0 15.3.0 14.4.0

# The rtoskit-libc release every toolchain is built with. crosstool-NG downloads that release's source archive
# (github.com/rtoskit-org/rtoskit-libc, tag v<version>) and checks it against the digests in
# crosstool-ng/packages/rtoskit/<version>/chksum. Maintained by tools/scripts/gcc-releases bump-libc.
RTOSKIT_LIBC_VERSION ?= 0.5.3

# The crosstool-NG commit the build downloads (a snapshot of its master that packages every GCC above), and the
# SHA-256 of that commit's source archive. Moved by tools/scripts/gcc-releases --ct-ng=latest.
CROSSTOOL_NG_REV ?= deacc28df92242014699eac9220e1d18fac3eeb6
CROSSTOOL_NG_SHA256 ?= c874ec5af243a7657959ff08ac82c140aab065db242f16cc9e7b07576555d965
