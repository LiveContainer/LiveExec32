# LiveExec32
Run 32-bit binaries on 64-bit iOS by passing through syscalls.

> [!NOTE]
> Some further work in this branch is done by LLM, mainly GPT-5.6 Sol; notable for implementing GDB Stub, Native Threads, more shims, etc.
> Its commit history is kept for later reference.
> Last commit before LLM is [760e9c7](https://github.com/LiveContainer/LiveExec32/commit/760e9c7da2856285a54404e7a6e00ee9fb99fd14)
>
> While I'd love to work more on it myself more, I can't really do it due to lack of time and I have too many side projects still left in the dust.
> I still try to review changes. LLM also validates them through test cases made by itself.
>
> Contributions are welcome.

This project is heavily based on [unidbg](https://github.com/zhkl0228/unidbg).

There are also missing syscalls that I have yet to provide to pass through. Please see [ARM32SyscallHandler.java](https://github.com/zhkl0228/unidbg/blob/master/unidbg-ios/src/main/java/com/github/unidbg/ios/ARM32SyscallHandler.java) and [DarwinSyscallHandler.java](https://github.com/zhkl0228/unidbg/blob/master/unidbg-ios/src/main/java/com/github/unidbg/ios/DarwinSyscallHandler.java) to implement them properly.

## Usage
- Compile this project using theos
- Generate the guest Objective-C shims, then build the guest frameworks:
```bash
gmake -C GuestMakefile generate-shims
gmake -C GuestMakefile
```
- Set up the guest root filesystem and install the built shim frameworks:
```bash
./GuestMakefile/pack-ramdisk.sh
```
  On the first run this downloads the iOS 10.3.3 restore ramdisk component
  (`058-75249-062.dmg`) from Apple's IPSW, decrypts it with `xpwntool`, and
  copies it into `Resources/RootFS` with `rsync -aH` (7z would break the HFS
  symlinks and dylib hardlink pairs that the guest dyld relies on).  The
  download and decrypted image are cached under `tmp/ipsw/`, so subsequent
  runs only reinstall the rebuilt frameworks.

  Override the sources with `RAMDISK_IPSW_URL`, `RAMDISK_IPSW_COMPONENT`,
  `RAMDISK_SETUP_DIR`, `RAMDISK_ROOT`, and `IOS_SYSTEM_ROOT` (the latter is
  the decrypted iOS 10.3.3 system root used for framework metadata and must
  be mounted while packing).  Requires `pzb`, `xpwntool`, `hdiutil`, and
  `rsync`.

- Launch a binary and profit.
```bash
.theos/out/LiveExec32 /var/mobile/ramdisk32/usr/bin/fdisk
```

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
eta son. No support for iOS 26+ yet until I can enable dual-mapping JIT for Dynarmic.

### Will this be available as a jailbreak tweak?
Yes, but no plan for this yet. This could be made as transparent as possible,
by allowing 32-bit apps to install and replace main binary with LiveExec32 when SpringBoard launches 32-bit app(?)

## License
Apache License 2.0
