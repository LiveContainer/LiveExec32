# Standalone runtime

[Back to the README](../README.md) · [Building](building.md)

Bundle LiveExec32 with a **decrypted ARM32 iOS app** to prepare it for launching
without LiveContainer or a separately installed LiveExec32. This is an
experimental packaging workflow: it does not enable JIT, sign the complete app,
or install it. The resulting app requires an iOS version supported by the bundled
runtime, a compatible signing and installation method, and working JIT access.

## Requirements

Run from this repository on macOS with Xcode Command Line Tools and `rsync`.
IPA handling uses the system `unzip` and `zip`; packaging does not require Python.
First [build the normal iOS runtime](building.md) (not `LC32_BUILD_CATALYST=1`),
or use a built LiveExec32 `.app` or `.ipa` containing standalone support.
Theos is not required to package an already built runtime. Older launchers
without bundled RootFS support are rejected with a rebuild message.

## Usage

Both the game and runtime inputs can independently be `.app` directories or
`.ipa` archives. Run the following commands from the repository root:

```bash
# Default: replace the input, saving the original as Game.app.lc32-backup.
bash Scripts/inject-standalone.sh "/path/to/Game.app" ".theos/obj/LiveExec32.app"

# IPA input is automatically extracted, patched, and archived back to an IPA.
# The original archive is saved as Game.ipa.lc32-backup.
bash Scripts/inject-standalone.sh "/path/to/Game.ipa" "/path/to/LiveExec32.ipa"

# Or leave the input untouched and create a new output (which must not exist).
bash Scripts/inject-standalone.sh --output "/path/to/Standalone.ipa" \
    "/path/to/Game.ipa" ".theos/obj/LiveExec32.app"
```

`--output` is optional. Without it, the script replaces the input only after
preparation succeeds, keeping an adjacent `.lc32-backup` of the original.
An existing backup is never overwritten. `--in-place` is accepted but unnecessary.
With `--output`, its parent directory must exist and its extension must match
the game input: `.app` produces `.app`, and `.ipa` produces `.ipa`.
Each IPA must contain exactly one app directly under `Payload/`.

The script reuses the jailbreak injector to add the ARM64 launcher while
preserving the original ARM32 slices and their SDK behavior. It embeds the
runtime's `Frameworks` and `RootFS`, preserves existing nonconflicting game
frameworks, and updates the minimum OS and CPU requirements. The launcher then
uses the bundled RootFS and the app's own data container. IPA repacking keeps
the original archive's other files, Unix permissions, and symbolic links;
hard links become separate files in the ZIP archive.

## Signing and limitations

Re-sign the **complete modified bundle**, including embedded native frameworks,
using your installation method. The injector's ad-hoc ARM64 signature alone is
not an installable app signature, and ordinary sideloading alone does not grant
JIT. An output IPA is repackaged, not fully signed; use an installer/signing tool
that signs its contents, or extract it, sign the app, and rearchive it under
`Payload/`. Keep the original backup outside that archive.

This script does not download games or decrypt executables. It refuses encrypted,
native ARM64, or already-injected inputs, existing output/backup paths, and
runtime-framework collisions. To repackage with a newer runtime, start with the
untouched original or a backup copied back to a `.app` directory or `.ipa` file.
Quit the app before replacing its bundle.

## Local tests

Run `gmake -C test check-standalone` for local packaging and launcher-path
regressions (the test harness requires Python 3). To also test with your built
runtime:

```bash
LC32_TEST_RUNTIME_APP="$PWD/.theos/obj/LiveExec32.app" gmake -C test check-standalone
```

These tests do not certify device signing, JIT, or game compatibility.
