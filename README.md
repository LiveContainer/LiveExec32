# LiveExec32
Run 32-bit binaries on 64-bit iOS by passing through syscalls.

The source code is currently very messy and may be prone to a lot of bugs (write overflow, etc). At least it works, but I will improve it later.

This project is heavily based on [unidbg](https://github.com/zhkl0228/unidbg).

There are also missing syscalls that I have yet to provide to pass through. Please see [ARM32SyscallHandler.java](https://github.com/zhkl0228/unidbg/blob/master/unidbg-ios/src/main/java/com/github/unidbg/ios/ARM32SyscallHandler.java) and [DarwinSyscallHandler.java](https://github.com/zhkl0228/unidbg/blob/master/unidbg-ios/src/main/java/com/github/unidbg/ios/DarwinSyscallHandler.java) to implement them properly.

## Usage
- Download and extract a ramdisk image using pzb and xpwn. For example, I chose the last 32-bit iPhone (armv7s) on the latest iOS 10.3.3:
```bash
pzb -g 058-75249-062.dmg http://appldnld.apple.com/ios10.3.3/091-23384-20170719-CA966D80-6977-11E7-9F96-3E9100BA0AE3/iPhone_4.0_32bit_10.3.3_14G60_Restore.ipsw
xpwntool 058-75249-062.dmg ramdisk.dmg -k
```
- Extract the dmg
```bash
7z x ramdisk.dmg
# extracted files go into ramdisk/
```

- Replace all of `/var/mobile/Documents/TrollExperiments` with your paths
- Compile this project using theos
- Generate the guest Objective-C shims, then build the guest frameworks:
```bash
gmake -C GuestMakefile generate-shims
gmake -C GuestMakefile
```
- Launch a binary and profit. Please note that chroot is internally done otherwise you will hit bad memory access errors. I'm investigating it and will provide a fix.
```bash
sudo .theos/out/LiveExec32 /var/mobile/ramdisk32/usr/bin/fdisk
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

## FAQ: can this be used to run 32-bit apps & integrate to LiveContainer?
Although this can execute simple C/C++/Objective-C binaries, more work needs to be done. The most important thing is to figure out how to proxy Objective-C classes, objects and method calls between host (64-bit) and guest (32-bit).

## License
Apache License 2.0
