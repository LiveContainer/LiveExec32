# Building LiveExec32

[Back to the README](../README.md) · [Configuration and diagnostics](configuration.md)

Run the commands below from the repository root.

## Host app and prerequisites

Initialize the submodules, then prepare the guest frameworks and root filesystem
below before building the host app with Theos:

```bash
git submodule update --init --recursive
```

The host build configures Dynarmic automatically with CMake and links its
static libraries into `LiveExec32Shared`. This requires CMake and Boost
1.57 or newer on the build machine.

## Guest frameworks

Generate the guest Objective-C shims, then build the frameworks:

```bash
gmake -C GuestMakefile generate-shims
gmake -C GuestMakefile
```

With GNU Make 4.3 or newer, independent frameworks and their source files are
built through the shared jobserver; pass `-jN` to cap concurrency. Guest
frameworks also share the SDK's MRC/ARC Clang module contexts, keeping a
cold module cache compact. Set `LC32_SHARE_GUEST_MODULE_CACHE=0` only when
diagnosing an isolated Clang module-cache issue.

### ARM32 linker

ARM32 guest frameworks, tests, and libiconv require a classic linker,
resolved with `xcrun --find ld-classic`. Newer Xcode linkers can emit
incorrect Thumb initializer pointers, and `-Wl,-ld_classic` no longer
selects the classic linker. If the selected toolchain does not provide it,
choose a toolchain that does or pass
`LC32_GUEST_LINKER=/absolute/path/to/ld-classic` to `gmake` (or in the
environment when running `GuestMakefile/build-libiconv.sh` directly).

With the guest SDK already prepared, check the linker and its ARM32
constructor/function-pointer output without requiring Theos:

```bash
gmake -C test check-guest-thumb-linker
```

### Guest SDK

The guest build downloads the third-party iOS 10.3 SDK archive to
`tmp/iPhoneOS10.3.sdk.tar.gz`, verifies its pinned SHA-256 checksum, and
extracts it atomically to `tmp/iPhoneOS10.3.sdk` for subsequent builds. Set
`ISYSROOT=/path/to/iPhoneOS10.3.sdk` to use an SDK obtained elsewhere, or
override `LC32_GUEST_SDK_URL` and `LC32_GUEST_SDK_SHA256` together when
using another mirror. The archive is hosted by a third party and remains
subject to Apple's SDK terms. Run `gmake -C GuestMakefile sdk` to prefetch
it without building. Theos still needs its separate iPhoneOS 16.5 SDK to
link the project.

### Shim generator checks

The generator reports methods disabled by unsupported type encodings,
separately from intentionally filtered/manual methods. Run
`Generator/GenerateShimAPI/test-object-out-pointers.sh` to check object
output marshalling and the captured-template disabled-method baseline.
Build the corresponding ARM32 runtime regression with
`gmake -C test object-out-parameters`.

See [Objective-C proxy bridge](ObjCProxy.md) for the bridge design and
marshalling contracts.

### libiconv

The same build also downloads and verifies Apple's `libiconv-50` source at
commit `6bcfda8c4720659e855c04ce72a8335fb4a67b0b`, then builds the armv7s
`/usr/lib/libiconv.2.dylib` used by older apps. The source and archive are
cached under `tmp/`; run `gmake -C GuestMakefile libiconv` to build only
that library. This library remains covered by the LGPL license shipped in
Apple's source archive; the guest root includes that license at
`/usr/local/OpenSourceLicenses/libiconv.txt`.

## Guest root filesystem

Set up the guest root filesystem and install the built shim frameworks:

```bash
./GuestMakefile/pack-ramdisk.sh
```

On the first run this downloads the iOS 10.3.3 restore ramdisk component
(`058-75249-062.dmg`) from Apple's IPSW, verifies its pinned checksum,
extracts its Img3 payload, and copies it into `Resources/RootFS` with
`rsync -aH` (7z would break the HFS symlinks and dylib hardlink pairs that
the guest dyld relies on). The download and extracted image are cached
under `tmp/ipsw/`, so subsequent runs only reinstall the rebuilt
frameworks.

Override the sources with `RAMDISK_IPSW_URL`, `RAMDISK_IPSW_COMPONENT`,
`RAMDISK_IPSW_COMPONENT_SHA256`, `RAMDISK_IMAGE_SHA256`,
`RAMDISK_SETUP_DIR`, and `RAMDISK_ROOT`. Framework bundle metadata is
tracked under `GuestMakefile/FrameworkInfoPlists`; override that snapshot
with `FRAMEWORK_INFO_ROOT`, or set `IOS_SYSTEM_ROOT` to test against another
mounted system image. Requires `pzb`, Python 3, `hdiutil`, and `rsync`.

## Assemble the host app

After packing the guest root filesystem, build the host app so it embeds the
updated resources:

```bash
gmake
```

For local execution tests on macOS, use `gmake LC32_BUILD_CATALYST=1` instead.
This opt-in mode rewrites and re-signs only the assembled app and its embedded
frameworks for Catalyst; a subsequent plain `gmake` restores normal iOS
artifacts without requiring `clean`.

## Launching a binary

On an iOS device, pass the ARM32 executable path to the installed launcher:

```bash
/path/to/LiveExec32.app/LiveExec32 /var/mobile/ramdisk32/usr/bin/fdisk
```

See [guest environment](configuration.md#guest-environment) for forwarding
environment variables and enabling guest dyld diagnostics.

The default build targets iOS and cannot run directly on macOS; use the
Catalyst build mode above for local execution tests.

## Release version and build metadata

`Version:` in the root `control` file is the single release-version source
(use a numeric version such as `0.0.1`). Builds copy it into
`CFBundleShortVersionString` for LiveExec32, LiveExec32Shared, and LC32HelpUI
before signing; tracked Info.plist templates are not rewritten. Theos can
still append package-only suffixes via `PACKAGE_BUILDNAME` or `PACKAGE_VERSION`.
`CFBundleVersion` remains each bundle's separate build number.
Startup logs include that release version, the 7-character Git commit
(with `-dirty` for tracked local changes), branch, device model, and OS.
Detached CI checkouts use `GITHUB_HEAD_REF`/`GITHUB_REF_NAME` for the branch;
source archives without Git metadata use `unknown` for the commit.
Run `gmake -C test check-build-info` for the metadata/logging regressions.
