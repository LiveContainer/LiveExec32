# Open-issue game crash triage — 2026-09-18

Scope: the [open LiveExec32 issues](https://github.com/LiveContainer/LiveExec32/issues),
including their comments and the one-page compatibility attachment in #37.
25 distinct crash/launch-failure game names: 19 eligible, 6 skipped under the
requested source restriction. Cut the Rope has two version-specific reports.
This is a partial reproduction pass, not a declaration that all reports are fixed.

Initial pass: three games installed; two startup failures fixed (Paper Toss and
Fruit Ninja); Bubble Ball is blocked by the simulator's OpenAL fallback.
VPN retry: The Heist, Angry Birds, and Snoopy downloaded and installed.
The Heist's delayed startup crash is fixed; Angry Birds reaches its opt-in
screen after shortening its simulator bundle path. Snoopy's reported `cString`
blocker is fixed, but a subsequent native UIKit thread assertion remains.
The follow-up pass includes new issue #46 (Plants vs. Zombies 2). All 19 eligible
games are installed (20 version-specific bundles, including both Cut the Rope
versions), and all received a normal LC URL launch attempt. Tomb Raider was
classified as native ARM64 by LC, so only 18 distinct games actually entered
the ARM32 emulator. Results below distinguish startup checks from the reported
gameplay failures; no touch tests were performed.
This pass fixed three initial blockers (PvZ2's Mach call, Spooky Pop's graphics
setters, and World of Goo's image retain API), but all three expose later
failures and are **not fully fixed**. Temple Run, Doodle Jump, Cut the Rope 1.5,
Where's My Water, and UNO reach menus or initial prompts without another fix.
Six more games were excluded by the requested source rule. Source changes
are local and uncommitted; nothing was pushed.

## Installation and test conditions

- Only [LegacyStore](https://legacystore.app) and the
  [approved IPA archive](https://stuffed18.github.io/ipa-archive-updated) were
  searched for installation sources. A download redirect from an approved
  catalog to its archive host was allowed. An issue supplying a separate,
  unapproved IPA link was skipped even if it also supplied an approved link.
- Catalog-selected copies are marked installable and contain ARM32 code.
  Completed downloads are checked against the catalog's size and SHA-1 before
  extracting and copying only `Payload/*.app`. No DRM bypass was performed.
- Simulator: iPhone 17 Pro Max, iOS 27.0; LiveContainer
  `com.kdt.livecontainer.UU7W52U79B`. Installed copies use separate
  `<bundle-id>.issue-eval.app` folders; existing copies were not overwritten.
  Angry Birds was subsequently renamed to `AB.eval.app` to avoid its own
  legacy path-length limit under the simulator's long container hierarchy.
  The follow-up queue uses compact, separate `eval<catalog-copy-id>.app` folders
  from the outset. Existing copies are not overwritten, and the two Cut the Rope
  versions have separate data containers.
- `LCAppInfo.plist` and data containers were created by LC, not by the installer.
  Bubble Ball, Paper Toss, and Fruit Ninja automatically received ARM32/JIT/Classic Mode
  settings. All three original executables lack an SDK version; LC chose its iOS 2.0
  floor (`131072`), rather than preserving an absent/zero SDK exactly.
- On retry, The Heist also received `spoofSDKVersion = 131072`, although its
  original ARMv7 executable explicitly declares SDK 6.1 (minimum OS 4.3).
  This is an LC auto-metadata mismatch; it was not manually corrected. The
  emulator recognizes the guest's SDK 6.1, but the LC process override is 2.0,
  so its viewport is not evidence of original-SDK behavior. Angry Birds lacks
  an executable SDK command and received the 2.0 floor; its Info.plist says
  `DTSDKName = iphoneos3.0`. Both games' LC metadata was created automatically.
- Snoopy's original executable declares SDK 7.0 (minimum OS 5.0), and the
  emulator recognizes that version, but LC also generated the process override
  2.0 for it. Metadata was auto-created, not supplied or edited by the installer.
- Follow-up ARM32 copies also received the 2.0 process override, including PvZ2
  (original SDK 8.0), Spooky Pop (8.1), Real Racing 3 (6.0), and Road Warrior
  (6.1). Their original SDKs are recognized by the emulator. Tomb Raider's
  metadata instead has `is32bit=false` and no ARM32/JIT/Classic Mode flags;
  its universal binary contains ARM64. No metadata was manually changed.
- No Mac keyboard/mouse automation or touch tests. Normal game checks use LC's
  launch URL. Separate debugger launches are for crash diagnosis only, not
  viewport/Classic Mode validation. Rendering and slowness are not treated as
  confirmed device defects.
- Baseline: local `dev` at `1f79917` (PR #44 merged locally). No push or GitHub
  issue changes were made.
- The simulator's existing LiveExec32 bundle points to `.theos/obj/LiveExec32.app`.
  The rebuilt local launcher is left converted/re-signed as a dylib for that LC
  test setup; no tracked launcher source was altered. A normal `gmake` restores
  the standard iOS executable. The pre-conversion launcher is also saved in the
  evidence directory as `LiveExec32.launcher-after-fix`. All debugger sessions
  are detached and the test game was stopped after verification.

## Eligible queue

All eligible entries now have an installed, checksum-verified candidate. Where
an issue omits a version, the listed version is a triage candidate, not a claim
to match the reporter's exact build. Reaching an opt-in prompt or menu is a
startup result, not gameplay validation.

| Issue | Game | Version reported → catalog candidate | Reported failure / current result |
| --- | --- | --- | --- |
| [#46](https://github.com/LiveContainer/LiveExec32/issues/46) | Plants vs. Zombies 2 | 3.2.1 → **catalog version 3.2, build 3.2.1 installed** | **Original Mach blocker fixed, game still crashes.** The exact issue stack reproduces before the fix; afterward crash-handler registration fails gracefully and startup proceeds to a separate `performSelector` assertion: target NSThread has no native thread. |
| [#43](https://github.com/LiveContainer/LiveExec32/issues/43) | [Snoopy's Street Fair](https://legacystore.app/app/474517295) | 1.28.0 → **1.28.0 installed** | **Reported `NSString cString` blocker fixed; game still crashes.** Subsequent failure is a native UIKit assertion when a background guest thread queries the status bar and triggers window creation. Device behavior untested. Filename/internal build can say 1.28.2. LC generated SDK 2.0 despite original SDK 7.0. |
| [#40](https://github.com/LiveContainer/LiveExec32/issues/40) | [UNO](https://legacystore.app/app/296845804) | 1.9.8x → **1.9.8 installed** | Reaches sound/firmware-warning prompts and remains running. No prompt dismissed. Reported Quick Play `FIONBIO` ioctl `0x8004667e` remains unimplemented/unvalidated; startup reaching a prompt does not fix that report. |
| [#38](https://github.com/LiveContainer/LiveExec32/issues/38) | [Spooky Pop](https://legacystore.app/app/932809014) | Unspecified → **0.2.10 installed** | **Reported graphics blocker fixed, game still crashes.** Added antialiasing and two font-cache setters. Retest progresses to missing `CFAllocatorCreate` in `nti_load_font_mem_nocopy`; a proper guest allocator-callback bridge remains needed. |
| [#29](https://github.com/LiveContainer/LiveExec32/issues/29) | [The Heist](https://legacystore.app/app/424724418) | Unspecified → **1.1.2 installed** | **Delayed startup crash fixed.** Added `NSValue` matrix widening/narrowing; normal LC URL launch passes the vault animation and reaches the in-game Sophia call screen. No touch/gameplay tests. LC generated the wrong process-SDK override (2.0 vs original 6.1). |
| [#28](https://github.com/LiveContainer/LiveExec32/issues/28) | [Fragger DS](https://legacystore.app/app/376620803) | Unspecified → **1.9.1 installed** | Still crashes. First observed blocker in this copy is `LC32HostToGuestArgument: unhandled type ^@` from an NSThread perform-selector callback, not the issue's missing nib class. Not fixed. |
| [#27](https://github.com/LiveContainer/LiveExec32/issues/27) | [Real Racing 3](https://legacystore.app/app/556164350) | 1.0.2 → **1.0.2 installed** | Gets past ImageIO, then fails on missing `CTFontCreateWithGraphicsFont` during font initialization. Exact baseline debugger reproduction captured; this later CoreText blocker is not fixed. |
| [#26](https://github.com/LiveContainer/LiveExec32/issues/26) | [Angry Birds](https://legacystore.app/app/343200656) | Unspecified → **1.2.0 installed** | **Reaches Crystal opt-in screen after a simulator install-path workaround.** Original missing locale symbol no longer blocks launch. Shortened this test bundle's folder name to avoid the game's resource-path limit; no source or game-binary change needed. No opt-in/touch/gameplay test. Original game, not Rio. |
| [#24](https://github.com/LiveContainer/LiveExec32/issues/24) | [Bubble Ball](https://legacystore.app/app/412089940) | Unspecified → **1.0 installed** | ImageIO loads. Simulator's silent OpenAL context leaves no native context; source allocation fails and ALmixer later dereferences a null mutex. Simulator blocker, not fixed; device behavior untested. |
| [#21](https://github.com/LiveContainer/LiveExec32/issues/21) | [Death Rally](https://legacystore.app/app/422020153) | Unspecified → **1.2 installed** | Confirmed guest SIGSEGV, `MemoryRead32(0x8dd07a9c)`, PC `0x31b9a`. Repeated recursive frames precede the fault. Root cause not established; not fixed or classified as simulator-only. |
| [#14](https://github.com/LiveContainer/LiveExec32/issues/14) | [Tomb Raider I](https://legacystore.app/app/663820495) | Unspecified → **1.0.2 installed** | **Not an ARM32 emulator test:** universal ARMv7/ARM64 bundle gets LC `is32bit=false`, then native simulator launch exits 1 before loading LiveExec32. Every installable copy in the retrieved LegacyStore catalog includes ARM64. No binary thinning or metadata override performed. |
| [#13](https://github.com/LiveContainer/LiveExec32/issues/13) | [Road Warrior](https://legacystore.app/app/461481850) | Unspecified → **1.4.2 installed** | Still running after 45 seconds, but screen is black. No startup crash observed in that window; loading/rendering limitation is not counted as a device defect or a successful menu launch. |
| [#37 attachment](https://github.com/LiveContainer/LiveExec32/issues/37) | [Doodle Jump](https://legacystore.app/app/307727765) | 2.4 → **2.4 installed** | Reaches menu with leaderboard opt-in prompt. No option selected; startup issue not reproduced. Gameplay untested. |
| [#37 attachment](https://github.com/LiveContainer/LiveExec32/issues/37) | [Temple Run](https://legacystore.app/app/420009108) | Unspecified → **1.1 installed** | Reaches main menu without another source change. Startup issue not reproduced; gameplay untested. |
| [#37 attachment](https://github.com/LiveContainer/LiveExec32/issues/37) | [Cut the Rope](https://legacystore.app/app/380293530) | 1.5 → **1.5 installed** | Reaches menu/news overlay without another source change. The reported crash after one minute of play remains untested because touch/gameplay is out of scope. |
| [#37 attachment](https://github.com/LiveContainer/LiveExec32/issues/37) | [Cut the Rope](https://legacystore.app/app/380293530) | 1.0 → **1.0 installed** | Confirmed startup abort in `LC32_releaseGuestOwnershipOnly`, not merely a black frame. Ownership lifecycle needs further diagnosis; not fixed. |
| [#37 attachment](https://github.com/LiveContainer/LiveExec32/issues/37) | [Where's My Water?](https://legacystore.app/app/449735650) | 1.0 → **1.0.0 installed** | Replacement catalog copy 159251 reaches main menu without another emulator fix. Initial copy 135440 matched catalog checksum but had ZIP CRC/offset errors; rejected before installation. Distinct from #11's XiYangYang game. |
| [#37 attachment](https://github.com/LiveContainer/LiveExec32/issues/37) | [Fruit Ninja](https://legacystore.app/app/362949845) | 1.0 → **1.0 installed** | **Startup blocker fixed; OpenFeint opt-in screen reached via LC URL.** Missing optional nib now permits the game's fallback. No opt-in, gameplay, or touch testing. |
| [#37 attachment](https://github.com/LiveContainer/LiveExec32/issues/37) | [World of Goo](https://legacystore.app/app/415997203) | 1.3 → **1.3 installed** | **Missing `CGImageRetain` fixed, game still crashes.** Retest progresses to guest `objc_msgSend` / `MemoryRead16(0xb1189024)` in `IPhoneEAGLView createFramebuffer`. Root cause remains undetermined. iPhone edition; attachment does not specify edition. |
| [#37 attachment](https://github.com/LiveContainer/LiveExec32/issues/37) | [Paper Toss](https://legacystore.app/app/317917431) | 1.0 → **1.0 installed** | **Startup fixed; main menu reached via LC URL.** Added `CGDataProviderCopyData` and `CGContextGetTextPosition`. Gameplay/touch untested. |

The attachment's proposed causes (memory leak, accelerometer, old layout) are
reporter hypotheses, not diagnoses established by this pass.

## Skipped because the issue supplies another download source

| Issue | Game | Unapproved issue-provided download source |
| --- | --- | --- |
| [#42](https://github.com/LiveContainer/LiveExec32/issues/42) | Super Monkey Ball 1.3 | Direct archive.org IPA, in addition to a LegacyStore page |
| [#41](https://github.com/LiveContainer/LiveExec32/issues/41) | Crash Bandicoot Nitro Kart 3D (`com.vgmobile.cnk2`) | Direct archive.org IPA, in addition to a LegacyStore page |
| [#36](https://github.com/LiveContainer/LiveExec32/issues/36) | Boomlings 1.43 | Direct archive.org IPA |
| [#25](https://github.com/LiveContainer/LiveExec32/issues/25) | Tiny Death Star | Direct archive.org/iOSObscura download directory |
| [#22](https://github.com/LiveContainer/LiveExec32/issues/22) | Cling Thing 1.1.1 | files.catbox.moe; later comment's failure is `GKScore.value` after a level |
| [#11](https://github.com/LiveContainer/LiveExec32/issues/11) | Where's My XiYangYang? (`com.disney.wheresmyxyy`) | MediaFire link in comments; issue title says Where's My Water |

No binaries were obtained through those issue-provided links. Mini Car Champion
also has a Google Drive link, but its report concerns rendering, so it is not
part of the crash queue. Other display/audio/localization reports and already
closed historical crash issues are not counted above.

## Reproduction details

### Paper Toss 1.0

LegacyStore copy `225588`, 5,420,358 bytes,
SHA-1 `5b250421f4cba8dadb7fc983bbf6c6366b6514cb`.
Guest stack: `platform::loadPng` → texture/menu initialization → dyld abort
because `_CGDataProviderCopyData` is absent from the guest CoreGraphics binary.

Implemented an append-only dispatcher opcode and guest export, forwarding to
native CoreGraphics and publishing the returned CFData with Copy ownership.
Retesting revealed the next missing symbol, `CGContextGetTextPosition`, which
is now implemented with explicit host-double to guest-float point conversion.
Added byte-content, null-input, and post-provider/image-release lifetime checks
plus fractional/negative text-position and text-matrix checks to
`test/coregraphics_bitmap.c`, and added both exports to the symbol audit.
ARM32 regression through the Catalyst emulator: all 19 checks passed, guest
exit 0. Graphics compatibility symbol audit: passed; all 25 CoreGraphics imports
in this Paper Toss executable resolve. The wider bitmap test also
emits two existing-style dead-receiver release warnings; assertions still pass.
Simulator normal LC URL retest reached the main menu. Initial black-screen
frames were slow startup, not a further crash: a live sample showed the
simulator's software OpenGL renderer and the next screenshot showed the menu.
No gameplay/touch test was performed. Screenshot:
`tmp/issue-games-20260918/papertoss-postfix-stable.png`. A second normal URL run
after the final nib-handler change also reached the menu; see
`papertoss-final-build.png` in that directory.

### Bubble Ball 1.0

LegacyStore copy `244847`, 3,115,369 bytes,
SHA-1 `5693caea6e00c8910e851d85cd1b8526ddb8ee4f`.
Normal LC URL launches terminate. Debugger captures guest `MemoryRead32(0)`,
block PC `0x73dd8`, with `r0 == 0`. Disassembly identifies an ALmixer mutex
wrapper dereferencing a null mutex wrapper before `pthread_mutex_lock`.
Caller `0x6c7ec` is setting an audio callback after initialization.

Reading the game's ALmixer error pool at the crash yielded
`Couldn't generate sources: Invalid Operation`. A second run stopped at native
`alGenSources`; native `alcGetCurrentContext()` returned NULL. This matches the
existing simulator-only silent-context fallback: `alcMakeContextCurrent` records
the guest token without activating a native context to avoid RemoteIO
timeouts/aborts, but `alGenSources` still calls native OpenAL. The resulting
initialization failure leads to the game's null mutex wrapper.

This is a confirmed limitation of the simulator audio path, not evidence that
the current device build has the same crash. No OpenAL behavior was changed:
removing the workaround risks the documented RemoteIO abort, while pretending
source allocation succeeded would require a real silent backend to preserve
OpenAL state correctly. No game-binary patch was made. Evidence:
`bubble-error-pool.log` and `bubble-native-context.log`.

### Fruit Ninja 1.0

LegacyStore copy `222643`, 6,989,006 bytes,
SHA-1 `53bdbdf72eb79905140030e1e0acaf64b5995aa5`.
The initial normal LC URL launch terminated with a native
`NSInternalInconsistencyException` for `RootControllerLandscapeOf`.
That optional nib is absent in both the original IPA and installed bundle;
`RootControllerOf.nib` exists. Disassembly of OpenFeint's `tryLoadController`
shows a nil-result fallback from the landscape probe to the ordinary nib.

The guest message bridge now handles only UIKit's matching missing-nib error
for `NSBundle loadNibNamed:owner:options:` and returns nil, allowing that fallback.
It does not install a global UIKit hook, rewrite the app, or suppress other
exceptions. This is consistent with the nil-result handling in Apple's archived
[nib-loading example](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/LoadingResources/CocoaNibs/CocoaNibs.html).

Verification:

- `gmake -C test check-legacy-nib-loading`: all six host checks passed, including
  successful-result preservation and rethrowing decode, awake, and nested-nib
  errors.
- ARM32 `lc32-uikit-nib-awakening` through Catalyst: inherited `awakeFromNib`,
  guest override/super calls, and missing optional nib checks passed; exit 0.
- Normal LC URL launch reaches the OpenFeint opt-in screen. No option was tapped
  and no service/account was enabled. Full menu/gameplay behavior is untested.
- Evidence: `fruit-crash-debug.log`, `nib-guest-regression.log`, and
  `fruit-after-nib-fix.png` under the local evidence directory.

### The Heist 1.1.2 — VPN retry

LegacyStore copy `128211`, 20,950,191 bytes,
SHA-1 `f82cd88142f988b6d09514191321ebf2cda20a3f`.
The normal LC URL launch initially shows the vault and then aborts without
touch input. LLDB confirms the same failure as #29: the delayed animation
boxes a `CATransform3D`, whose 16-float ARM32 encoding is unsupported by
`NSValue(LC32Bytes)`.

Added an explicit 16-float/16-double layout conversion in both directions.
Raised the bounded sized-indirect capacity from 64 to 128 bytes, the size of
the native matrix; the descriptor format and bounds checks are unchanged.
The guest box continues to retain its original ARM32 bytes, while genuinely
native-created boxes are narrowed when copied back to guest memory.

The extended `lc32-nsvalue-bytes` regression reproduced the abort before the
fix and passed all 18 checks afterward (guest exit 0). It checks all matrix
elements, native box contents, native-created values, `objCType`, category
round trips, and both guest/native buffer canaries, alongside the existing
selector/pointer tests. After rebuilding, the normal LC URL launch passed
the vault animation and reached the game's Sophia incoming-call screen.
No real phone call or touch interaction was performed.

Evidence: `heist-crash-debug.log`, `nsvalue-baseline.log`, `nsvalue-fixed.log`,
`heist-after-transform.png`, and `heist-stable.png`. Gameplay remains untested;
the LC-generated SDK mismatch is recorded under test conditions above.

### Angry Birds 1.2.0 — VPN retry

LegacyStore copy `98342`, 9,335,757 bytes,
SHA-1 `773654df998a26b96c1d836e9d65ec1a80313b97`.
Normal URL launch still exits, but not at the originally missing locale
constant. LLDB now shows an uncaught guest `io::IOException` from
`io::PathName` during `MaskedImage` construction. The throwing branch in the
game binary uses the message `Too long path name` and a roughly 250-byte
path buffer. A guest-stack dump confirms the directory
`<simulator bundle>/data_iphone/shaders/` is already 242 characters; the
failing constructor appends `sprite-straightalpha` (19 more characters).
Renamed only this task's test bundle folder to `AB.eval.app`, preserving all
files and LC's auto-created metadata/data container. No game binary was modified.
The next normal LC URL launch reaches the Crystal opt-in screen and remains
alive. No option was selected and no service/account was enabled. This confirms
the startup failure in this copy was caused by its simulator installation path;
gameplay and device behavior remain untested. Screenshot: `angrybirds-shortpath.png`.

Evidence: `angrybirds-crash-debug.log`, `angrybirds-path-disassembly.log`,
`angrybirds-maskedimage-disassembly.log`, `angrybirds-path-debug.log`, and
`angrybirds-guest-stack.bin`.

### Snoopy's Street Fair 1.28.0 — VPN retry

LegacyStore copy `104302`, 191,719,817 bytes,
SHA-1 `c913f327d870e27d9e78c75e1d51b8b8320e46df`.
LC automatically created metadata and a new data container. Normal URL launch
failed after startup; a from-launch debugger run captured
`cannot forward guest -[NSTaggedPointerString cString]: unsupported return encoding`.

Added the deprecated `NSString cString` method using the existing guest-owned
string-buffer adapter and `[NSString defaultCStringEncoding]`. It does not
assume UTF-8 or return a native pointer to guest code. This follows the method
contract documented in the local iOS 10.3 SDK's `NSString.h`.

The extended ARM32 string regression reproduced the failure before the fix
and passed all 19 checks afterward, including six new deprecated-method checks
for ASCII, native-created strings, empty strings, Unicode/default encoding,
embedded NULs, and mutable strings. The 18-check matrix regression, 19-check
bitmap regression, three guest nib checks, and six host nib checks still pass.
All guest tests exit 0. `git diff --check` passes.

Evidence: `snoopy-start-crash-debug.log`, `string-bytes-baseline.log`,
`string-bytes-fixed.log`, and the `*-final.log` regression logs.

The final normal LC URL retest still terminates. The new failure is distinct:
`BSServiceMainRunLoopQueue assertBarrierOnQueue` traps on a background native
guest thread. The native stack runs through `valueForKey:` →
`UIApplication statusBarWithWindow:` → status-bar/window creation →
`FBSScene attachLayer:`. The from-launch LLDB retest reproduces the same native
trap; there is no further `cString` forwarding failure in that run.

This is **not** a claim that Snoopy is now playable, nor that the remaining
crash is simulator-only. Device behavior and the effect of LC's incorrect SDK
override are untested. No general UIKit thread rerouting or assertion
suppression was added: synchronous main-thread rerouting can deadlock guest
threads, and returning nil for private KVC queries would change app behavior
without establishing the caller's expectations. Evidence:
`snoopy-next-crash-debug.log` and `snoopy-native-ui-thread.ips` (a retained
copy of the normal URL launch's macOS diagnostic report).

### Plants vs. Zombies 2 — issue #46 follow-up

LegacyStore copy `267926`, 44,546,405 bytes,
SHA-1 `88894aca44aecba750f1f58c0e86fa4d719b6a9f`. Its Info.plist confirms
short version `3.2`, build `3.2.1`, matching the catalog's version/build split.
Normal LC URL launch crashes. The baseline debugger reproduces the issue's
`Unhandled Mach message id 3415`, `task_swap_exception_ports`, and game offsets
`0x442d4e` / `0x448952` exactly.

Added bounded ARM32 MIG replies for task set/get/swap exception-port requests
(3413–3415). Since guest exception delivery is not implemented, well-formed
self-task requests return `KERN_NOT_SUPPORTED`, rather than aborting or falsely
claiming registration succeeded. The host task's exception handlers are never
changed: guest ARM32 reporters must not intercept native ARM64 exceptions.
Malformed layouts/NDR/descriptors receive `MIG_BAD_ARGUMENTS`; receive capacity
and target task are validated. Copy-send port ownership is preserved.

Verification: 15 host checks pass, including malformed and truncated messages,
reply canaries, unknown-ID fallthrough, and unchanged send/receive rights. The
ARM32 Mach regression passes all 47 individual checks plus its overall PASS
line (guest exit 0); six checks cover public get/set/swap stubs and port lifetime.
Actual game retest outcome is recorded in the eligible table above. Evidence:
`debug-267926.log`, `mach-rpc-current.log`, `host-regressions-current.log`,
and `postfix-267926.*`.

The game logs the failed optional Mach registration and continues, then aborts
at `NSObject+LC32ThreadPerforming.m`: `performSelector target NSThread has no
native thread`. Stack includes the game's `+0x48913c` / `+0x46a598` offsets
and `LC32NSThreadEntry`. This later thread-mapping failure is not suppressed or
classified as simulator-only. See `postdebug-267926.log`; the normal URL retest
also terminates. **PvZ2 is not yet playable.**

### Spooky Pop and World of Goo — CoreGraphics follow-up

Spooky Pop copy `285633` reproduces the missing
`CGContextSetAllowsAntialiasing` in `nti_surface_create` during native font-cache
initialization. Added that native forwarding operation plus the same game's
other two missing CoreGraphics imports, `CGContextSetAllowsFontSubpixelPositioning`
and `CGContextSetShouldSubpixelQuantizeFonts`. These retain the native context
semantics; they are not no-op success stubs. Dispatcher opcodes are append-only.

World of Goo (iPhone) copy `30269` reproduces missing `CGImageRetain`.
Implemented it with the existing guest CF ownership adapter, paired with
`CGImageRelease`. All CoreGraphics imports in both executables now resolve.

The ARM32 bitmap regression passes all 24 checks, guest exit 0: three new pixel
checks distinguish disallowed/enabled/should-disabled antialiasing, and two
new image checks cover retain identity, NULL, and survival after releasing both
the original owner and bitmap context. The font setters are exercised with both
boolean values and NULL contexts; their exports are also audited. Existing
matrix (18) and string (19) checks still pass. Graphics symbol audit and
`git diff --check` pass. Game retest outcomes are recorded in the eligible table.

Evidence: `debug-285633.log`, `spooky-baseline.stderr`, `debug-30269.log`,
`cg-current.log`, `nsvalue-current.log`, `string-current.log`, and
`postfix-285633.*` / `postfix-30269.*`.

Spooky Pop's follow-up debugger run passes those graphics calls and fails on
missing `CFAllocatorCreate` in `nti_load_font_mem_nocopy`. Implementing this
requires respecting guest allocation callbacks and lifetime, not merely
returning the default allocator. No such fallback was added. See
`postdebug-285633.log`; the game still terminates on a normal URL launch.

World of Goo's normal URL retest also terminates. Its follow-up debugger gets
past `CGImageRetain` and captures a different failure: guest `objc_msgSend`
tries `MemoryRead16(0xb1189024)` from `IPhoneEAGLView createFramebuffer +0x1b8`,
called by `layoutSubviews`. This memory fault is not counted as a mere rendering
artifact or assumed simulator-only. Root cause is not established and no
receiver/ownership validation was bypassed. See `postdebug-30269.log`.

### Remaining launch-pass evidence

Normal launch results/screenshots use `smoke-<catalog-copy-id>.json/.png`:
Cut the Rope 1.0 `222781`, Fragger DS `157561`, Temple Run `11256`,
Cut the Rope 1.5 `179734`, Road Warrior `330218`, Spooky Pop `285633`,
Doodle Jump `194497`, Death Rally `3341`, World of Goo `30269`, UNO `224859`,
Tomb Raider I `89775`, PvZ2 `267926`, Where's My Water `159251`, and
Real Racing 3 `20849`. Each check waits at least 45 seconds after the normal
launch URL, saves a simulator screenshot, and records whether the LC process
is still present. A running process alone is not treated as a successful menu.

Separate baseline debugger evidence uses `debug-<id>.log`. Fragger's native
argument-type diagnostic is also retained in `fragger-baseline.stdout`.
Tomb Raider exits 1 before loading LiveExec32; its metadata and debugger log
are evidence of a native-mode selection, not a new guest crash.

## Download and evidence notes

Archive transfers measured roughly 12–20 KB/s. Snoopy and several Heist copies
timed out; smaller Bubble Ball and Paper Toss downloads completed by resuming.
Fruit Ninja's 7 MB download completed in about 7 minutes 16 seconds.
Do not install the incomplete `.ipa` files.

After the user confirmed the VPN was connected, resuming The Heist 1.1.2
completed at approximately 112 KB/s; Angry Birds 1.2.0 completed at 172 KB/s.
Snoopy continued to transfer slowly on one connection. Four bounded ranges
from the same catalog URL completed its remaining 154 MB in about 6 minutes
7 seconds (roughly 105–134 KB/s per range). The assembled 191,719,817-byte IPA
matched its catalog SHA-1 before installation. Earlier partial files and
range records are retained; no VPN settings or Mac input were changed.

Local evidence is under `tmp/issue-games-20260918/` (ignored by Git): cached
issues/comments, both source catalogs, candidate copy metadata, downloaded
attachment, checksums/install records, build logs, debugger reports, simulator
screenshots, and resumable partial downloads. This directory contains third-party
app binaries and should not be committed or redistributed with the code change.

The final remaining queue completed using bounded parallel HTTP ranges, then
full assembled SHA-1/size verification. Where's My Water copy `135440` matches
its catalog SHA-1 but contains a damaged `swampy-HD.png` and bad ZIP offsets;
it was rejected before copying into LC. Alternate same-version copy `159251`
passes checksum/extraction and reaches its menu. PvZ2 has valid plist values
not representable in JSON; the installer was adjusted to extract required
fields individually without rewriting the app's Info.plist. LCAppInfo was
still created only by LC.
