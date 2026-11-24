# LiveExec32
Run 32-bit binaries on 64-bit iOS by passing through syscalls.

Not all apps will work and will mostly run into missing symbols issue. Please open an issue for that.

> [!NOTE]
> Some further work in this branch is done by LLM, mainly with Codex; notable for implementing GDB Stub, Native Threads, more shims, etc.
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

Build with Theos, CMake, and Boost 1.57 or newer. See the
[build guide](docs/building.md) for SDK requirements and classic linker setup.

```bash
git submodule update --init --recursive
gmake -C GuestMakefile generate-shims
gmake -C GuestMakefile
gmake -C GuestMakefile install
gmake
```

### IPA build
The IPA build is only meant to be used in LiveContainer, since it provides existing app/container management and convenient JIT enabler options.
<table>
  <tr>
    <td> Stable </td>
    <td align="center">
      Not yet available
    </td>
    <td align="center">
      Not yet available
    </td>
  </tr>
  <tr>
    <td> Nightly </td>
    <td>
      <a href="https://altdirect.app/?url=https://github.com/LiveContainer/LiveExec32/releases/download/nightly/source.json&r=livecontainer" target="_blank">
        <img src="https://raw.githubusercontent.com/StikStore/altdirect/refs/heads/main/assets/png/AltSource_Blue.png" alt="Add AltSource" width="200" />
      </a>
    </td>
    <td>
      <a href="https://github.com/LiveContainer/LiveExec32/releases/download/nightly/com.kdt.liveexec32_0.0.1.ipa" target="_blank">
        <img src="https://raw.githubusercontent.com/StikStore/altdirect/refs/heads/main/assets/png/Download_Blue.png" alt="Download .ipa" width="200" />
      </a>
    </td>
  </tr>
</table>

### Jailbreak tweak
The jailbreak tweak lets you sideload decrypted 32-bit apps directly to the system and launch just like any other apps.
During install, LiveExec32 shim is injected to 32-bit app so installd doesn't reject it and makes everything easier to handle.

Releases only include iOS 15+ rootless build for now. Jailbreak repo will be added later.

### Standalone runtime

You can bundle LiveExec32 with a decrypted ARM32 `.app` or `.ipa` to run without
LiveContainer or a separately installed runtime. See [Standalone runtime](docs/standalone.md)
for instructions. Use your signer and bring your own JIT enabler method.

### Command line
Launch an ARM32 binary with the installed app's executable:

```bash
/path/to/LiveExec32.app/LiveExec32 /path/to/arm32-binary
```

You can also launch with the 32-bit dyld_shared_cache, for example:
```bash
NATIVE_GUEST_THREADS=1 ROOT_PATH=/Volumes/Greensburg14G60.N41N42N48N49OS /path/to/LiveExec32.app/LiveExec32 /Volumes/Greensburg14G60.N41N42N48N49OS/usr/libexec/backboardd
```

- [Building](docs/building.md): prerequisites, downloads, guest RootFS, and macOS testing.
- [Configuration and diagnostics](docs/configuration.md): logging, guest environment, and SDK/UIKit compatibility.
- [Objective-C proxy bridge](docs/ObjCProxy.md): architecture, ownership, and ABI details.
- [Compatibility reports](docs/compatibility/): game testing, fixes, and remaining issues.

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
### Will this allow running encrypted 32-bit apps (ie directly installed from App Store)?
Idk, need to research into this next

## License
Apache License 2.0
