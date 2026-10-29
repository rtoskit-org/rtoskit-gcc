# rtoskit-gcc

Builds `arm-none-eabi` GCC cross toolchains with [crosstool-NG](https://github.com/crosstool-ng/crosstool-ng),
using [rtoskit-libc](https://github.com/sgstreet/rtoskit-libc) as the C library, for the last three GCC major
releases at their latest minor release (currently 16.2.0, 15.3.0 and 14.4.0).

Each toolchain has:

- **Multilibs** for the Cortex-M cores rtoskit-libc supports (table below). The `release` (size) and `speed`
  builds of rtoskit-libc are installed for every multilib.
- **GDB 17** with Python.
- **`local-exec` as the default TLS model**, which rtoskit-libc's `thread_local` needs. `-ftls-model=` on the
  command line still overrides it.
- **C only.** C++ is tracked in [#2](https://github.com/sgstreet/rtoskit-gcc/issues/2) and in
  rtoskit-libc's C++ issue.

## Dependencies

	sudo apt install -y gcc g++ gperf bison flex texinfo help2man make libncurses5-dev python3-dev autoconf automake \
		libtool libtool-bin gawk wget curl bzip2 xz-utils unzip patch libstdc++6 rsync git gettext

- **GNU make 4.4 or newer.** rtoskit-libc's build needs it, and the build stops with a message if it is older.
- **qemu-user** (`qemu-arm`) to run programs linked with the Linux test port, and rtoskit-libc's tests.
- Access to the private rtoskit-libc repository, for the git submodule.

## Build

	$ make                              # all three versions, one after the other (about 11 minutes each on 16 cores)
	$ make GCC_VERSIONS=16.2.0          # one version

`make` first runs `setup`, which initialises the submodules (`external/crosstool-ng`, `external/rtoskit-libc`).
Each toolchain lands in `images/gcc-arm-none-eabi-<major>-<minor>-<patch>.tar.xz`, with the crosstool-NG build log
beside its work directory in `build/release/compilers/arm-none-eabi/gcc-<version>/`. Sources are downloaded to
`downloads/`.

| Goal | |
|---|---|
| `make distclean` | Delete the build tree, `build/release/` |
| `make realclean` | Delete `build/`, `images/` (the packaged toolchains) and `downloads/` |
| `make info` | Show the build configuration |

## Multilibs

`compilers/arm-none-eabi/t-rtoskit` lists the multilibs and `compilers/arm-none-eabi/rtoskit/multilib.map` maps each
to the rtoskit-libc architecture it is built from. Options GCC maps onto a listed multilib (`-mcpu=cortex-m4`,
`+dsp`, `softfp`, Armv8.1-M, a double-precision Armv8-M FPU, …) use the closest one.

| Multilib directory | rtoskit-libc `ARCH_CROSS` | Cores |
|---|---|---|
| `.` and `thumb/v6-m/nofp` | `armv6-m` | Cortex-M0, M0+, M23 |
| `thumb/v7-m/nofp` | `armv7-m` | Cortex-M3 |
| `thumb/v7e-m/nofp` | `armv7-m` | Cortex-M4, M7 without an FPU |
| `thumb/v8-m.main/nofp` | `armv7-m` | Cortex-M33 without an FPU |
| `thumb/v7e-m+fp/hard` | `armv7e-m` | Cortex-M4F, M7 with the single-precision FPU |
| `thumb/v7e-m+dp/hard` | `armv7e-m-dp` | Cortex-M7 with the double-precision FPU |
| `thumb/v8-m.main+fp/hard` | `armv8-m.main` | Cortex-M33 with FPU (Cortex-M55 and M85 use it too, without MVE) |

The default (no `-mcpu`) is Thumb Armv6S-M soft-float. ARM-state and Armv4/5 targets are not supported. Adding GCC's
full `rmprofile` set is tracked in [#3](https://github.com/sgstreet/rtoskit-gcc/issues/3).

## Using a toolchain

	$ tar -xf images/gcc-arm-none-eabi-16-2-0.tar.xz
	$ export PATH=$PWD/gcc-arm-none-eabi-16-2-0/bin:$PATH
	$ arm-none-eabi-gcc -mcpu=cortex-m4 -mfloat-abi=hard --specs=rtoskit.specs -Os -T board.ld startup.o app.c -o app.elf

`--specs=rtoskit.specs` (installed in the sysroot `lib/`):

- compiles with only rtoskit-libc's headers, as `-std=gnu23` unless you pass your own `-std`;
- links `-lc` and `-lrtos-none` from the multilib that matches your `-mcpu`/`-march`/`-mfloat-abi`, with
  `--gc-sections`;
- drops the toolchain's start files, so your startup code and linker script provide `_start`, the memory layout and
  the heap bounds (see rtoskit-libc's *Porting to your RTOS*).

| Option | Effect |
|---|---|
| `--speed` | Link the speed build of the library (`lib/<multilib>/speed/`) |
| `--libc=<variant>` | `nofloat`, `minimal-printf` or `tinymalloc` instead of `libc.a` |
| `--port=<name>` | Link `librtos-<name>.a` instead of `librtos-none.a` |
| `--specs=rtoskit-linux.specs` | The Linux test port: run the program under `qemu-arm -cpu max` |

The default TLS model is `-ftls-model=local-exec`, set with GCC's `--with-specs`. Its `__aeabi_read_tp` comes from
the port.

## Updating the GCC versions

`compilers/arm-none-eabi/versions.inc` lists the versions. `tools/scripts/gcc-releases` keeps it current and never
commits:

	$ tools/scripts/gcc-releases check              # configured, newest on ftp.gnu.org, and whether crosstool-NG packages them
	$ tools/scripts/gcc-releases update              # move each major to its latest minor
	$ tools/scripts/gcc-releases rotate              # add the newest major, drop the oldest (16 15 14 -> 17 16 15)
	$ tools/scripts/gcc-releases bump-libc [REF]     # move the rtoskit-libc submodule and stage it
	$ tools/scripts/gcc-releases --dry-run rotate    # show what would change

If the pinned crosstool-NG does not package a version, `--ct-ng=latest` (or `--ct-ng=<ref>`) moves the
`external/crosstool-ng` submodule. If no crosstool-NG revision has it, the script writes the package into
`compilers/arm-none-eabi/crosstool-ng/packages/gcc/<version>/` and lists the package it replaces in
`crosstool-ng.remove`.

## Layout

| Path | |
|---|---|
| `compilers/arm-none-eabi/arm-none-eabi.mk` | The build: one crosstool-NG run per version |
| `compilers/arm-none-eabi/arm-none-eabi.defconfig.in` | The crosstool-NG configuration, shared by every version |
| `compilers/arm-none-eabi/crosstool-ng/` | Laid over a copy of the crosstool-NG submodule: the `rtoskit` libc backend |
| `compilers/arm-none-eabi/t-rtoskit`, `rtoskit/` | The multilib list, its map and the spec files |
| `external/` | Submodules: crosstool-NG and rtoskit-libc |
