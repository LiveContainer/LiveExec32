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

The guest UIKit build writes `LC32_UIKIT_COMPATIBILITY` (default `1`) to
`GuestMakefile/.theos/override.h`, which host builds include automatically.
Repack the guest after changing the setting before building the host app.
See [UIKit compatibility configuration](configuration.md#compile-without-uikit-compatibility-hooks).

With GNU Make 4.3 or newer, independent frameworks and their source files are
built through the shared jobserver; pass `-jN` to cap concurrency. Guest
frameworks also share the SDK's MRC/ARC Clang module contexts, keeping a
cold module cache compact. Set `LC32_SHARE_GUEST_MODULE_CACHE=0` only when
diagnosing an isolated Clang module-cache issue.

### ARM32 linker

ARM32 guest frameworks, tests, and libiconv use `xcrun --find ld` through
`Scripts/guest-ld`; `ld-classic` is not required. Modern ld can omit the Thumb
bit in stored function pointers and the executable entry point. The wrapper
repairs dyld rebase locations and `LC_MAIN` using `N_ARM_THUMB_DEF` symbols
before Theos strips or signs the output. It does not change ARM pointers,
data pointers, instructions, or dynamic bindings.

The wrapper requires Python 3 and unstripped, thin ARM32 PIE executables,
dylibs, or bundles with opcode-based dyld fixups. Unsupported formats fail
before the wrapper publishes the output. Strip/sign only after linking.
Host ARM64 builds do not use this wrapper.

With the guest SDK already prepared, check the linker and its ARM32
constructor/function-pointer output without requiring Theos:

```bash
gmake -C test check-guest-thumb-linker
gmake -C test check-guest-linker
```

The second check covers parser rejection/idempotence and builds mixed
ARM/Thumb, Objective-C, block, and C++ probes. Set `LC32_TEST_RUNTIME` to a built
Catalyst `LiveExec32.app/LiveExec32` launcher to execute the probes as well.

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

`Generator/GenerateShimAPI/test-selector-alias.sh` checks generated methods
after guest swizzling, including Everyplay's renderbuffer selector alias.
`Generator/GenerateShimAPI/test-simple-structs.sh` checks generated geometry,
`CGVector`, `UIOffset`, and `CLLocationCoordinate2D` argument/result marshalling
through a host-call recorder, plus ARM32 syntax checks when the guest SDK is present.
CGFloat-based structs share `LC32Host/Guest2Floats`, `4Floats`, and `6Floats`
converters; `NSValue` also uses `16Floats` for `CATransform3D` storage.
`gmake -C test check-float-structs` checks these conversions, unaligned buffers,
write boundaries, precision, signed zero, infinities, and NaNs. Fixed-width
coordinate/SceneKit layouts are not widened by these helpers.
This does not replace an ARM32 runtime test of the aggregate trampoline.
Unsupported pointer and larger struct layouts remain disabled.

`sh test/bundle_class_lookup_host.sh` checks that `NSBundle classNamed:` loads
and resolves a guest class instead of returning a native superclass proxy.
`gmake -C test bundle-class-lookup` builds the ARM32 CoreTelephony regression
without prelinking that framework; it skips runtimes without the native bundle.

`gmake -C test graphics-method-adapters mapkit-methods framework-value-methods`
builds ARM32 runtime checks for native path ownership, layer rendering into
guest bitmap buffers, MapKit loading/regions, and SceneKit/MapKit value boxing.
The value tests also exercise generated `CGVector`, `UIOffset`, and coordinate
methods across the real guest/host bridge, including raw storage bounds for
the new fixed-layout boxes. `array-sort-function` covers mutable and immutable
callback sorting, including the optional hint.

`gmake -C test cf-type-ownership` builds the opaque CoreFoundation ownership
regression. It checks typed CG, CF, and Objective-C retain/release paths with
finite-lived color spaces, including a native-only owner and final proxy
destruction. Run it alongside `coregraphics-bitmap`, `graphics-method-adapters`,
and `native-proxy-release` when changing CF cleanup.

`gmake -C test corefoundation-uuid corefoundation-low-risk` covers native
CFUUID creation, 16-byte ARM32 values, constant identity, and file-security
UUID setters/copy getters. The UUID fixture also builds against native macOS
CoreFoundation for comparison; CFUUID must not be represented by NSUUID.

`gmake -C test kvc-floating-ivars kvc-ivar-ownership guest-fp-return`
checks synthetic float/double ivar accessors, object ownership, and native
floating-point callbacks. The floating-ivar test covers inherited and
underscore keys, per-class bindings, real accessor precedence, exact bits,
and adjacent storage guards. It also builds natively for KVC comparison.

`gmake -C test gamekit-properties gamekit-achievement-properties` builds
local-only ARM32 GameKit regressions. They compare guest properties with native
state, including `GKScore`'s initialized-value flag, signed/unsigned 64-bit
values, legacy category aliases, leaderboard and matchmaking settings, and
read-only player, achievement, challenge, and turn-based model properties.
No authentication, score submission, or matchmaking is performed. GameKit
forwards many accessors dynamically, so method-list captures omit them; their
public ARM32 signatures must still be present in the generator template.
The guest GameKit build disables implicit property synthesis and treats missing
accessors as errors to prevent silent guest-only storage.

See [Objective-C proxy bridge](ObjCProxy.md) for the bridge design and
marshalling contracts.

`gmake -C test openal-smoke openal-streaming` builds the ARM32 OpenAL bridge
regressions. The streaming suite checks queue completion, playback controls,
offsets, context isolation, and object/error lifetimes. Run them in Simulator
to exercise the clocked silent backend; real-device playback remains native.
The silent backend produces no sound, and `LC32_OPENAL_SILENT_CONTEXT=0` opts
out for simulator-only native-audio diagnostics.

`gmake -C test foundation-temporary-files` builds the ARM32 temporary-file
regression: guest `mkstemp`/POSIX I/O and native `NSFileHandle`/`NSData` must
access the same files. When running it in a simulator, set `SIMCTL_CHILD_TMPDIR`
to an existing writable directory outside the guest home and `/var` (for example,
under the checkout's `test/.theos/`) to exercise the explicit temp-directory
mount. Repeat with the default temp directory; both runs should pass eight checks.

`gmake -C test check-legacy-nib-classes SIMULATOR_UDID=booted` runs a native
UIKit regression for the removed `UIRoundedRectButton` nib class. It checks
registration, preservation of existing classes, and native button decoding
without installing or foregrounding a fixture app.

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
gmake -C GuestMakefile install
```

This target runs `GuestMakefile/pack-ramdisk.sh` on the existing build products;
it does not build a Theos package or install anything on a device. Use
`gmake -C GuestMakefile all install` to build first and then pack, including
with parallel make. The script can still be run directly.

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

Nightly builds generate `packages/source.json` with
`Scripts/generate-nightly-source.py` and publish it alongside the IPA and Debian
package. The source uses the packaged app's version, build number, bundle ID,
minimum iOS version, and IPA size, plus the current commit and workflow link.
The nightly source is available as
[source.json](https://github.com/LiveContainer/LiveExec32/releases/download/nightly/source.json).
