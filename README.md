# rtoskit-gcc

Builds `arm-none-eabi` GCC cross toolchains with [crosstool-NG](https://github.com/crosstool-ng/crosstool-ng),
using [rtoskit-libc](https://github.com/sgstreet/rtoskit-libc) as the C library, for the last three GCC major
releases at their latest minor release (currently 16.2.0, 15.3.0 and 14.4.0).

Each toolchain has:

- **Multilibs** for the Cortex-M cores rtoskit-libc supports (table below). The `release` (size) and `speed`
  builds of rtoskit-libc are installed for every multilib.
- **rtoskit-libc** built from its release source (`RTOSKIT_LIBC_VERSION`, currently 0.5.0) with `-funwind-tables
  -mpoke-function-name` (`CT_LIBC_RTOSKIT_CFLAGS`), so a backtrace passes through library frames and each library function
  carries its name in the code before it.
- **GDB 17** with Python.
- **`local-exec` as the default TLS model**, which rtoskit-libc's `thread_local` needs. `-ftls-model=` on the
  command line still overrides it.
- **C and C++.** `arm-none-eabi-g++` builds against rtoskit-libc's headers and `__cxa_atexit` /
  `__cxa_thread_atexit`, with exceptions, RTTI, `thread_local` destructors and a hosted libstdc++ (`<string>`,
  `<vector>`, `<iostream>`, `<regex>`, `<ranges>`, `<chrono>`, `std::println`, ...), without wide characters.
  libstdc++ is configured by `compilers/arm-none-eabi/gcc-patches/0002-libstdcxx-add-rtoskit-libc-os-port.patch`
  (`--with-rtoskit-libc`), which asks rtoskit-libc what it provides through the `<rtoskit-libc.h>` header it installs.
  `std::random_device` reads `getentropy`, which fails on a board whose port has no entropy source.
  `-fno-exceptions` and `-fno-rtti` work. `std::stacktrace` needs `-lstdc++exp` (libbacktrace)
  and, under `-fno-exceptions`, `-funwind-tables`; it captures frames on the target, but entries have no description
  or file unless the executable can be opened (it cannot on a board; use `addr2line` on the ELF).
  `gcc-patches/0003-libbacktrace-use-atomic-compare-exchange.patch` makes libbacktrace compare and swap through the
  `__atomic` builtins, which v6-m has as library calls and the legacy `__sync` ones it does not.
  Threads are configured `--enable-threads=posix` over rtoskit-libc's `<pthread.h>`, so `std::thread`, `std::mutex` and
  the other mutex classes (`std::shared_mutex` too), `std::condition_variable`, `std::call_once`, thread-safe local
  statics, `std::future` and `std::async` work, and `steady_clock` waits use `pthread_cond_clockwait` and
  `pthread_mutex_clocklock`. `gcc-patches/0004-gthr-posix-use-rtoskit-libc-pthreads.patch` makes GCC's `gthr-posix.h`
  call every pthread function strongly, since a static link would otherwise find threads inactive, and send
  `std::call_once` through rtoskit-libc's `__libc_call_once_eh`, so an exception from its function leaves the flag unset
  and the next call runs the function again. `std::thread` takes the library's default stack size and priority.
  `<mutex>` includes `<stdlib.h>`, which declares C23's `once_flag`, so `once_flag` is ambiguous with `std::once_flag`
  under `using namespace std`.
  `std::filesystem` does nothing useful.

## Dependencies

	sudo apt install -y gcc g++ gperf bison flex texinfo help2man make libncurses5-dev python3-dev autoconf automake \
		libtool libtool-bin gawk wget curl bzip2 xz-utils unzip patch libstdc++6 rsync git gettext

- **GNU make 4.4 or newer.** rtoskit-libc's build needs it, and the build stops with a message if it is older.
- **qemu-user** (`qemu-arm`) to run programs linked with the Linux test port, and **dejagnu** for `gcc-torture`:
  `sudo apt install -y qemu-user dejagnu`.

## Build

	$ make                              # all three versions, one after the other (about 11 minutes each on 16 cores)
	$ make GCC_VERSIONS=16.2.0          # one version

The build downloads its sources to `downloads/` and checks each against a pinned digest: crosstool-NG at the commit
`CROSSTOOL_NG_REV` (SHA-256 `CROSSTOOL_NG_SHA256`) and the rtoskit-libc release `RTOSKIT_LIBC_VERSION`, which
crosstool-NG fetches as the package `compilers/arm-none-eabi/crosstool-ng/packages/rtoskit/<version>` (its `chksum` holds
the digests of the release's source archive, `v<version>.tar.gz`). All three are in
`compilers/arm-none-eabi/versions.inc`. There are no submodules and nothing to initialise.
Each toolchain lands in `images/gcc-arm-none-eabi-<major>-<minor>-<patch>.tar.xz`, with the crosstool-NG build log
beside its work directory in `build/release/compilers/arm-none-eabi/gcc-<version>/`. Sources are downloaded to
`downloads/`.

| Goal | |
|---|---|
| `make distclean` | Delete the build tree, `build/release/` |
| `make realclean` | Delete `build/`, `images/` (the packaged toolchains) and `downloads/` |
| `make info` | Show the build configuration |
| `make BUILD_MANUALS=n` | Skip the GCC and binutils manuals (faster; no TeX needed) |
| `make PROGRESS_BAR=y\|n` | crosstool-NG's spinner and clock. On by default only when stderr is a terminal, so logs (CI) stay readable |

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

- compiles with only rtoskit-libc's headers (and, for C++, libstdc++'s), as `-std=gnu23` for C unless you pass your
  own `-std`;
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

## Validating a toolchain

Three scripts check an unpacked toolchain; the first two run in CI on every toolchain it builds:

	$ tools/scripts/validate-toolchain gcc-arm-none-eabi-16-2-0
	$ tools/scripts/test-installed gcc-arm-none-eabi-16-2-0
	$ tools/scripts/gcc-torture gcc-arm-none-eabi-16-2-0 /tmp/torture "-mcpu=cortex-m4 -mfloat-abi=hard"

| Script | Checks |
|---|---|
| `validate-toolchain` | The multilib list, which multilib each core selects, the default TLS model, gdb with Python, and that a threaded `printf`/`sinf`/`thread_local` program links with every multilib (release and speed) and runs under `qemu-arm`. For C++ it runs the threading classes (`std::thread`, the mutexes, `std::condition_variable`, `std::call_once`, `std::future`) and times `sleep_for`, `wait_for` and `try_lock_for` against `steady_clock` and `system_clock`. It checks the POSIX thread model and that libstdc++ was configured with every feature `<rtoskit-libc.h>` names. A C program must link none of the thread functions |
| `test-installed` | rtoskit-libc's unit tests built against the *installed* toolchain only (no in-tree include or library paths) for eight core options, release and speed, and run under `qemu-arm`. Tests that need the library's internals are skipped. |
| `gcc-torture` | GCC's own `gcc.c-torture/execute` tests (about 1700 programs, eight optimisation levels each) through DejaGnu on the multilib the options select. Failures that cannot pass here are listed in `tools/dejagnu/torture.xfail`. |

They need `qemu-arm` (`qemu-user`), and `gcc-torture` also `runtest` (`dejagnu`). All of them run programs through the Linux test port under `qemu-arm`: nothing yet runs the default `none` port on a bare-metal core ([#5](https://github.com/sgstreet/rtoskit-gcc/issues/5)).

## CI

`.github/workflows/ci.yml` builds every version in `versions.inc` from scratch, then runs `validate-toolchain` and `test-installed` on it, and uploads the toolchain. The GCC torture tests run on request (*Run workflow*, *torture*).

- **Variable `CI_RUNNER`** (optional): the label of a larger runner. A build uses about 15 GB of disk and takes an hour or more on a standard runner.
- The build uses `BUILD_MANUALS=n` (no PDF or HTML manuals), which is also available locally.

## Updating the GCC versions

`compilers/arm-none-eabi/versions.inc` lists the versions. `tools/scripts/gcc-releases` keeps it current and never
commits:

	$ tools/scripts/gcc-releases check              # configured, newest on ftp.gnu.org, and whether crosstool-NG packages them
	$ tools/scripts/gcc-releases update              # move each major to its latest minor
	$ tools/scripts/gcc-releases rotate              # add the newest major, drop the oldest (16 15 14 -> 17 16 15)
	$ tools/scripts/gcc-releases bump-libc [VERSION] # build with an rtoskit-libc release (default: the newest tag)
	$ tools/scripts/gcc-releases --dry-run rotate    # show what would change

If the pinned crosstool-NG does not package a version, `--ct-ng=latest` (or `--ct-ng=<ref>`) moves the
crosstool-NG commit (`CROSSTOOL_NG_REV` and its digest in `versions.inc`). If no crosstool-NG revision has it, the script writes the package into
`compilers/arm-none-eabi/crosstool-ng/packages/gcc/<version>/` and lists the package it replaces in
`crosstool-ng.remove`.

## Layout

| Path | |
|---|---|
| `compilers/arm-none-eabi/arm-none-eabi.mk` | The build: one crosstool-NG run per version |
| `compilers/arm-none-eabi/arm-none-eabi.defconfig.in` | The crosstool-NG configuration, shared by every version |
| `compilers/arm-none-eabi/crosstool-ng/` | Laid over the downloaded crosstool-NG: the `rtoskit` libc backend and the package of the rtoskit-libc release |
| `compilers/arm-none-eabi/t-rtoskit`, `rtoskit/` | The multilib list, its map and the spec files |
| `compilers/arm-none-eabi/gcc-patches/` | GCC patches applied to every version (the libstdc++ OS port, libbacktrace, the POSIX thread model) |
| `tools/scripts/` | `gcc-releases` (versions), `validate-toolchain`, `test-installed`, `gcc-torture` (validation) |
| `tools/dejagnu/` | The DejaGnu board for `gcc-torture` and its expected failures |
| `.github/workflows/ci.yml` | CI: build and validate every toolchain |
