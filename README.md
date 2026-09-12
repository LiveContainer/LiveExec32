# LiveExec32
Run 32-bit binaries on 64-bit iOS by passing through syscalls.

Not all apps will work and will mostly run into missing symbols issue. Please open an issue for that.

> [!NOTE]
> Some further work in this branch is done by LLM, mainly GPT-5.6 Sol; notable for implementing GDB Stub, Native Threads, more shims, etc.
> Its commit history is kept for later reference.
> Last commit before LLM is [dbd36e3](https://github.com/LiveContainer/LiveExec32/commit/dbd36e3e42e4e675e6fd542d4a487b61dbdc755d)
>
> While I'd love to work more on it myself more, I can't really do it due to lack of time and I have too many side projects still left in the dust.
> I still try to review changes. LLM also validates them through test cases made by itself.
>
> Contributions are welcome.

This project is heavily based on [unidbg](https://github.com/zhkl0228/unidbg).

There are also missing syscalls that I have yet to provide to pass through. Please see [ARM32SyscallHandler.java](https://github.com/zhkl0228/unidbg/blob/master/unidbg-ios/src/main/java/com/github/unidbg/ios/ARM32SyscallHandler.java) and [DarwinSyscallHandler.java](https://github.com/zhkl0228/unidbg/blob/master/unidbg-ios/src/main/java/com/github/unidbg/ios/DarwinSyscallHandler.java) to implement them properly.

## Usage
- Initialize Dynarmic, then compile this project using Theos:
```bash
git submodule update --init --recursive
gmake
```
  The host build configures Dynarmic automatically with CMake and links its
  static libraries into `LiveExec32Shared`. This requires CMake and Boost
  1.57 or newer on the build machine.
  For local execution tests on macOS, use
  `gmake LC32_BUILD_CATALYST=1`. This opt-in mode rewrites and re-signs only
  the assembled app and its embedded frameworks for Catalyst; a subsequent
  plain `gmake` restores normal iOS artifacts without requiring `clean`.
  Verbose host bridge, loader, memory, syscall, and thread logs are compiled
  out by default. Build with `gmake LC32_DEBUG_LOGS=1` to enable them; rebuild
  with `gmake LC32_DEBUG_LOGS=0` (or plain `gmake`) to disable them again.
  Errors and actionable warnings remain enabled in both modes, and existing
  specialized runtime trace controls are unchanged.

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

  The jailbreak injector normally floors the arm64 shim's SDK at iOS 11.
  To experiment with the ARM32 app's original SDK instead, build the deb
  with `gmake PACKAGE_FORMAT=deb LC32_PRESERVE_GUEST_SDK=1 package` (plus
  your usual package-scheme/install options). The shim's minimum OS remains
  iOS 11. This affects newly injected executables; it does not rewrite apps
  that already contain an arm64 shim, or change LiveContainer's SDK override.
  Missing/zero SDK values are preserved as zero. Rebuild without this flag
  to restore the default for subsequent injections.
  Pre-iOS-8 guests still get their legacy `HOME/LiveExec32.app` bundle alias
  in LiveContainer, independently of UIKit compatibility mode. Its target
  is relative to the selected guest container, so relocating LiveContainer's
  outer container keeps it valid. Matching older absolute aliases are upgraded;
  unrelated entries and the standalone installer's two-link layout are preserved.

  Low-SDK execution remains experimental. The host supplies narrow UIKit
  layout-policy compatibility for layout guides, text-effects and keyboard windows
  without raising the process SDK. An opt-in native Simulator regression is
  available with `sh test/uikit_legacy_sdk_layout.sh --device UDID --baseline`;
  it tests actual SDK 0, 7, 8, 10.3, and 11 Mach-O variants, needs an already
  booted Simulator, and installs/removes only its own temporary test apps.
  Processes with an effective SDK before iOS 8 use UIKit's native legacy
  rotation and geometry instead of LiveExec32's adapters, avoiding a duplicate
  turn. This follows dyld's process-SDK query, including LiveContainer's SDK
  override installed before LiveExec32 loads. Thus an unclamped old SDK in
  LiveContainer disables these adapters, while existing SDK-11-clamped
  executables or LiveContainer overrides retain them. The native test also
  includes policy-only cases with an SDK-11 executable and test-provided
  effective SDKs; those isolate this selection without spoofing UIKit itself.
  To compare native UIKit geometry on
  newer hosts, launch with `LC32_DISABLE_UIKIT_COMPATIBILITY=1` in the host
  process environment. This disables the host and guest canvas, orientation,
  and synthetic-root adaptations, but retains the low-SDK Auto Layout fixes,
  missing-API wrappers, and bridge recursion protection. The setting is read
  once at launch; restart without it to restore the SDK-based default.
  Pre-iOS-11 processes also repair nonfinite preferred-font results from
  CoreText's legacy text-style tables (including Vietnamese line metrics).
  Valid fonts are unchanged. Broken results use their resolved native face
  and a concrete descriptor; missing accessibility sizes fall back to the
  largest normal legacy category, not the modern accessibility-size table.
  This repair stays enabled when geometry compatibility is disabled and
  does not change the process SDK or language preferences. Run the native
  font regression with `sh test/uikit_legacy_font_metrics.sh --device UDID`.
  On pre-iOS-8 hosts, native alerts also use matched modern presentation,
  layout and animator paths so action sheets do not collapse or remove their
  presenting view. The policy overrides are limited to the native methods
  handling an alert; ordinary window rotation retains the original SDK's
  behavior. These hooks install together only when the required native
  methods are available. The font regression also checks text-field alerts,
  titled/untitled action sheets, repeated animated/nonanimated dismissal,
  presenter visibility and preservation of the native window policy.
- Generate the guest Objective-C shims, then build the guest frameworks:
```bash
gmake -C GuestMakefile generate-shims
gmake -C GuestMakefile
```
  With GNU Make 4.3 or newer, independent frameworks and their source files are
  built through the shared jobserver; pass `-jN` to cap concurrency. Guest
  frameworks also share the SDK's MRC/ARC Clang module contexts, keeping a
  cold module cache compact. Set `LC32_SHARE_GUEST_MODULE_CACHE=0` only when
  diagnosing an isolated Clang module-cache issue.

  The generator reports methods disabled by unsupported type encodings,
  separately from intentionally filtered/manual methods. Run
  `Generator/GenerateShimAPI/test-object-out-pointers.sh` to check object
  output marshalling and the captured-template disabled-method baseline.
  Build the corresponding ARM32 runtime regression with
  `gmake -C test object-out-parameters`.

  The guest build downloads the third-party iOS 10.3 SDK archive to
  `tmp/iPhoneOS10.3.sdk.tar.gz`, verifies its pinned SHA-256 checksum, and
  extracts it atomically to `tmp/iPhoneOS10.3.sdk` for subsequent builds. Set
  `ISYSROOT=/path/to/iPhoneOS10.3.sdk` to use an SDK obtained elsewhere, or
  override `LC32_GUEST_SDK_URL` and `LC32_GUEST_SDK_SHA256` together when
  using another mirror. The archive is hosted by a third party and remains
  subject to Apple's SDK terms. Run `gmake -C GuestMakefile sdk` to prefetch
  it without building. Theos still needs its separate iPhoneOS 16.5 SDK to
  link the project.

  The same build also downloads and verifies Apple's `libiconv-50` source at
  commit `6bcfda8c4720659e855c04ce72a8335fb4a67b0b`, then builds the armv7s
  `/usr/lib/libiconv.2.dylib` used by older apps. The source and archive are
  cached under `tmp/`; run `gmake -C GuestMakefile libiconv` to build only
  that library. This library remains covered by the LGPL license shipped in
  Apple's source archive; the guest root includes that license at
  `/usr/local/OpenSourceLicenses/libiconv.txt`.
- Set up the guest root filesystem and install the built shim frameworks:
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

- Launch a binary and profit.
```bash
.theos/obj/LiveExec32.app/LiveExec32 /var/mobile/ramdisk32/usr/bin/fdisk
```

Host environment variables are isolated from the guest by default. To pass a
specific value, prefix its name with `LC32_GUEST_ENV_`; the launcher strips
that prefix when constructing the guest environment. For example:

```bash
LC32_GUEST_ENV_NSUnbufferedIO=YES \
  .theos/obj/LiveExec32.app/LiveExec32 /var/mobile/ramdisk32/usr/bin/fdisk
```

`HOME`, `LC32_OBJC_TRACE`, `NATIVE_GUEST_THREADS`, and
`DYLD_SHARED_REGION` remain launcher-owned and cannot be overridden through
this mechanism. `DYLD_PRINT_*` diagnostics are disabled by default, but can
be enabled explicitly, for example with
`LC32_GUEST_ENV_DYLD_PRINT_SEGMENTS=1`.

## Design
- LiveExec32 has most of the codebase and references from [unidbg](https://github.com/zhkl0228/unidbg), so it also uses Dynarmic as the dynamic translator of ARMv7 code to ARM64.
- The entry point starts from dyld, so it has all of dyld APIs isolated from that of host.
- In `CallSVC`, it goes through a long list of guest functions that copy memory regions from input and to output using a page table. Perhaps page bound checks can be added to allow fastpath memory access.
- Has a crash reporter and symbolicator for guest code.
- Can emulate bind mount points
- More to be explored...

### Guest framework sources

Hand-written guest framework code lives in `GuestFrameworks/<Framework>` and
is tracked. `GuestFrameworks/.generated/<Framework>` is recreated by
`GuestMakefile/generate-shims.sh` and is intentionally ignored; do not commit
files from it. The generator currently obtains 12 private UIKit fallback
classes from the installed Catalyst runtime, so those particular shims remain
host-dependent until their iOS 10 signatures are captured in the tracked
templates.

## FAQ
### Can this be used to run 32-bit apps & integrate to LiveContainer?
Yes. The bundled Dynarmic revision includes the dual-mapping/TXM JIT path
required by iOS 26+, while non-iOS hosts remain single-mapped by default.

### Will this be available as a jailbreak tweak?
Yes eta now. During install, LiveExec32 shim is injected to the pending 32-bit
app so installd doesn't reject it and makes everything easier to handle.

## Will this allow running encrypted 32-bit apps (ie directly installed from App Store)?
Idk, need to research into this next

## License
Apache License 2.0
