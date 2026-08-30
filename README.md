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
- Generate the guest Objective-C shims, then build the guest frameworks:
```bash
gmake -C GuestMakefile generate-shims
gmake -C GuestMakefile
```
  With GNU Make 4 or newer, independent frameworks and their source files are
  built through the shared jobserver; pass `-jN` to cap concurrency. Guest
  frameworks also share the SDK's MRC/ARC Clang module contexts, keeping a
  cold module cache compact. Set `LC32_SHARE_GUEST_MODULE_CACHE=0` only when
  diagnosing an isolated Clang module-cache issue.

  The guest build downloads the third-party iOS 10.3 SDK archive to
  `tmp/iPhoneOS10.3.sdk.tar.gz`, verifies its pinned SHA-256 checksum, and
  extracts it atomically to `tmp/iPhoneOS10.3.sdk` for subsequent builds. Set
  `ISYSROOT=/path/to/iPhoneOS10.3.sdk` to use an SDK obtained elsewhere, or
  override `LC32_GUEST_SDK_URL` and `LC32_GUEST_SDK_SHA256` together when
  using another mirror. The archive is hosted by a third party and remains
  subject to Apple's SDK terms. Run `gmake -C GuestMakefile sdk` to prefetch
  it without building. Theos still needs its separate iPhoneOS 16.5 SDK to
  link the project.
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
Yes, but no plan for this yet. This could be made as transparent as possible,
by allowing 32-bit apps to install and replace main binary with LiveExec32 when SpringBoard launches 32-bit app(?)

## License
Apache License 2.0
