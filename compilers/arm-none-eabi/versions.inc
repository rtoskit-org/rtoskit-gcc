# The GCC releases built, newest major first: the latest minor release of each of
# the last three majors. Maintained by tools/scripts/gcc-releases (check, update, rotate).
# Override on the command line to build a subset, e.g. make GCC_VERSIONS=16.2.0
GCC_VERSIONS ?= 16.2.0 15.3.0 14.4.0
