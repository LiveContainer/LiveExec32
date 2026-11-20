# Open-issue game crash triage — 2026-09-18

Scope: the [open LiveExec32 issues](https://github.com/LiveContainer/LiveExec32/issues),
including their comments and the one-page compatibility attachment in #37.
25 distinct crash/launch-failure game names: 19 eligible, 6 skipped under the
requested source restriction. Cut the Rope has two version-specific reports.
This is a partial reproduction pass, not a declaration that all reports are fixed.

Initial pass: three games installed; two startup failures fixed (Paper Toss and
Fruit Ninja); Bubble Ball was blocked by the simulator's OpenAL fallback
(fixed in the November 15 follow-up below).
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
| [#29](https://github.com/LiveContainer/LiveExec32/issues/29) | [The Heist](https://legacystore.app/app/424724418) | Unspecified → **1.1.2 installed** | **Startup crash fixed; first level of all four puzzle types completed on 2026-11-17.** Saved completions survive cold launch with original SDK 6.1 + Classic Mode. The new shared-runtime saved-canvas fallback preserves centered/scaled presentation and footer input on simulator resume. SpringBoard still drops its Classic flag; device/full-game completion remains unverified. |
| [#28](https://github.com/LiveContainer/LiveExec32/issues/28) | [Fragger DS](https://legacystore.app/app/376620803) | Unspecified → **1.9.1 and 1.11.4 installed** | **Missing nib class, invalid-file-descriptor crash, initial root layout, and enlarged controls fixed in 1.11.4.** Legacy SDK + Classic Mode now renders the menu and tutorial correctly on the simulator. JIT mapping optimization reduces normal LC startup from about 20 to 12 seconds. Device behavior and full gameplay unverified; 1.9.1 retains its previously observed splash result. |
| [#27](https://github.com/LiveContainer/LiveExec32/issues/27) | [Real Racing 3](https://legacystore.app/app/556164350) | 1.0.2 → **1.0.2 installed** | Gets past ImageIO, then fails on missing `CTFontCreateWithGraphicsFont` during font initialization. Exact baseline debugger reproduction captured; this later CoreText blocker is not fixed. |
| [#26](https://github.com/LiveContainer/LiveExec32/issues/26) | [Angry Birds](https://legacystore.app/app/343200656) | Unspecified → **1.2.0 installed** | **Reaches Crystal opt-in screen after a simulator install-path workaround.** Original missing locale symbol no longer blocks launch. Shortened this test bundle's folder name to avoid the game's resource-path limit; no source or game-binary change needed. No opt-in/touch/gameplay test. Original game, not Rio. |
| [#24](https://github.com/LiveContainer/LiveExec32/issues/24) | [Bubble Ball](https://legacystore.app/app/412089940) | Unspecified → **1.0 installed** | **2026-11-15: simulator OpenAL blocker fixed.** The clocked silent backend permits startup, level 1 completion, and transition to level 2. No audible output; device behavior untested. |
| [#21](https://github.com/LiveContainer/LiveExec32/issues/21) | [Death Rally](https://legacystore.app/app/422020153) | Unspecified → **1.2 installed** | **Startup resource-path blocker fixed for LiveContainer; simulator also needs a short data path.** On the physical iPhone 15 Pro Max, both engine revs and gunfire were audible over the soundtrack in a race (2026-11-20). Full gameplay coverage remains unverified. |
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

### Fragger DS follow-up — 2026-11-16

Installed Legacy Store [copy 222552](https://legacystore.app/ipa/222552),
version 1.11.4/build 468, in a separate LC entry and save container. The
36,202,700-byte IPA matches SHA-1 `1aa25d078033c4f90049a81d43e9d049516ed040`.
LC generated its metadata automatically; testing selected the current shared
runtime, Classic Mode, and the executable's original SDK 6.0. The older 1.9.1
install and saves were retained.

Baseline LLDB stopped in `UINibDecoderDecodeObjectForValue` with the reported
`Could not instantiate class named UIRoundedRectButton` exception during
`UIApplication _loadMainNibFileNamed:bundle:`. Native class lookup returned nil.
The 1.11.4 main nib uses optimized `NIBArchive` encoding; the older 1.9.1 copy
uses a keyed binary plist and did not reproduce this exception during its
splash-screen stall.

`LegacyNibClasses.mm` registers the missing name as a native UIButton subclass
only when UIKit does not already provide it. It inherits native decoding,
including archived button type and state, without swizzling the decoder,
rewriting the nib, or substituting arbitrary unknown classes. This is a
class-resolution repair independent of the orientation compatibility switch.

The native simulator regression fails class lookup without the repair and
passes eight checks with it: class identity/inheritance, repeat registration,
unrelated missing classes, archived-name decoding, round-button type, stateful
titles, control state, and frame. Existing optional-nib filtering checks pass.
After the nib fix, a startup-paused debugger run stopped on
`-[NSConcreteFileHandle writeData:]: Bad file descriptor` from an NSURLConnection
data callback. The handle was initialized with descriptor `-1`, not closed too
early. Guest `mkstemp` failed its parent-directory `stat`: native
`NSTemporaryDirectory()` returned LC's own simulator container under `/Users`,
outside the selected guest home and existing `/var` mounts. Guest filesystem
translation incorrectly prefixed RootFS to that native path.

Bootstrap now mounts Foundation's native temporary directory once alongside
the other host-backed directories. This preserves native/guest file identity
without changing `NSFileHandle` error handling or patching the game. The ARM32
`foundation-temporary-files` regression fails both directory lookup and
`mkstemp` on the previous runtime, then passes eight checks on the fixed one:
directory visibility, creation, native write, POSIX read, unlink, unchanged
ENOENT behavior, native creation, and guest reading of the native-created file.
Both an explicit temp directory outside the guest home and the simulator's
default temp directory pass. The eight native nib-class checks still pass.

Retested the rebuilt shared runtime on the iPhone 17 Pro Max/iOS 27 simulator.
Normal LC URL launch stays running past the former crash; LLDB sampled the
main thread actively drawing through OpenGL. A separate cold-launch trace
records descriptor `5` entering the native handle initializer and a subsequent
`writeData:` call, with zero hits on `objc_exception_throw`. The simulator
display was initially black; the November 17 follow-up below confirms that
content eventually appears. This is a verified crash fix, not a gameplay pass.
Device behavior remains unverified. No game binary or nib patch was made.
LLDB was detached and closed.

Evidence: `/private/tmp/lc32-fragger-20261116.K4iU8D/`, especially
`fragger-1.11.4-exception.lldb.txt`, `fragger-after-nib-fix.lldb.txt`,
`nib-class-build.log`, `nib-class-regression.log`, `open-events.log`,
`temporary-files-before.log`, `temporary-files-after.log`,
`temporary-files-default.log`, `fixed-handle-events.log`,
`fixed-cold-launch.lldb.txt`, and `after-temp-fix-running.lldb.txt`.

**Startup profiling — 2026-11-17:** three fresh-process, normal LC URL launches
first captured the visible menu at 20.4, 20.7, and 19.4 seconds. These are
screenshot observations, not exact first-frame timestamps (1–2 second sampling,
plus roughly 0.4 second capture latency). Saves and caches were retained; no
debugger or touch input was used. The menu is still clipped; startup timing
does not validate the layout or gameplay.

Native sampling shows two processes: LC first loads its SwiftUI frontend, then
relaunches into the selected game/runtime. Both stages spend substantial time
in native dyld dependency loading. In the game process, repeated
`oaknut::CodeBlock::unprotect/protect` calls change permissions across the entire
JIT cache for each translated block; `__mprotect` accounts for 572 samples at a
requested 10 ms interval. Sampling itself stretches startup (about 24 seconds
in this run), so these counts are hotspot evidence, not precise phase timings.

A controlled direct-launch comparison with the same launcher/runtime and
`DYNARMIC_DUAL_MAPPED=0` versus `1` reaches the visible menu in roughly 12 versus
7 seconds. The launcher now selects the existing dual-mapped JIT on the iOS
Simulator before loading the runtime. It preserves explicit environment values,
ordinary device/Catalyst defaults, and the existing jailbreak-package policy.
No JIT implementation, game binary, or protection bypass was added.

Three subsequent normal LC URL launches first capture the menu at **13.4,
12.4, and 11.4 seconds**—about 37% lower mean observed startup time than the
three baseline runs. This is a simulator result with warm caches, not a device
performance claim. Native framework loading and LC's frontend/relaunch still
contribute to the remaining delay.

The follow-up profile contains no sampled `CodeBlock::protect/unprotect` or
`__mprotect` hotspot. Validation passes all 32 launcher-policy/override checks,
the standalone suite (23 pass, two optional skips), and ARM32 Thumb callbacks,
native pthread smoke (72,000 increments), VM remap, and all eight temporary-file
checks with the new default. Full host build and `git diff --check` pass.

Timing screenshots/logs: `/private/tmp/lc32-fragger-timing.jKQieQ/`.
Profiles, build log, launcher backups, and regression output:
`/private/tmp/lc32-fragger-profile.lTneOP/`.

**Initial landscape layout — 2026-11-17:** LLDB confirmed a landscape root
with 568×320 bounds containing a fixed 320×568 OpenGL view. Both GL viewport
and renderbuffer were 320×568, so the defect preceded GL allocation. Fragger
attaches its root view, shows the window, assigns `rootViewController`, then
creates the renderer immediately from that controller's bounds. Modern UIKit
had already assigned the landscape interface orientation, but left the root's
view unrotated until after renderer creation. `layoutIfNeeded` alone did not
complete that orientation layout.

The native legacy-rotation unit now completes the window's **existing**
orientation layout after an attached, registered modern-policy root is assigned
during startup. It uses UIKit's existing orientation update, without choosing a
new orientation, changing renderer frames/autoresizing, hard-coding dimensions,
or checking game classes. Legacy-policy and rootless renderers retain their
deferred startup lifecycle; SDK 8+ remains outside this compatibility unit.

The fixed-size-renderer fixture verifies landscape bounds before construction,
no early legacy callbacks, and matching root/renderer bounds after startup.
Against the original rotation unit it fails the initial landscape-bounds and
settled renderer-fit assertions. With the fix, all 14 selected SDK 6.1/11 cases
pass (startup, modern/legacy explicit roots, manual rotation, disabled rotation,
lifecycle, and backing ownership). The shared-runtime build and diff check pass.
Fragger's normal LC URL launch with original SDK 6.0 and Classic Mode now shows
the correctly arranged menu; simulator HID tapping Play opens world selection.
LLDB confirms that root bounds, OpenGL child, viewport, and renderbuffer are all
568×320. The debugger was detached and closed after these checks.
The rotation fix alone still left oversized tutorial controls. That distinct
screen-scale mismatch is addressed below, rather than by resizing game views.

Evidence: `/private/tmp/fragger-layout-baseline-regression.log`,
`/private/tmp/fragger-layout-final-regression.log`,
`/private/tmp/fragger-final-geometry.lldb.txt`,
`/private/tmp/fragger-final-menu.png`, and
`/private/tmp/fragger-final-tutorial-advance.png`.

**Legacy screen scale on newer UIKit — 2026-11-17:** this is an iPhone-only
IPA (`UIDeviceFamily = [1]`). UIKit loaded `menu.png` as a 157×53-point image
backed by 314×106 pixels, while Fragger's exact `UIScreen.scale == 2` Retina
check failed against the simulator's 3× scale. Its director and OpenGL view
therefore stayed at 1×, making texture pixels appear as enlarged game units.

The existing adapter used `UIScreenMode._sizeWithLevel:`, which this iOS 27
runtime no longer implements. Disassembly shows the public scale getter reading
the stored scale directly and the mode getter reading display-mode pixels;
screen/scene traits and display configuration also expose 3×, not a separate
legacy application scale. The adapter retains its UIKit-derived path when that
private API exists. Otherwise, for pre-iOS-8 guests only, it caps the main
display at the historical 2× maximum and applies the same ratio to that display's
mode sizes. This explicit compatibility constant is necessary in the fallback;
there is no hard-coded resolution, game identifier, asset-name rule, or button
resizing. Native callers, external displays, SDK 8+ guests, compatibility-off
builds, and the runtime disable switch remain unchanged.

The rebuilt runtime reports guest scale 2 while native scale remains 3.
Fragger now detects Retina support and uses director scale 2, 568×320 logical
view bounds, and matching 1136×640 GL viewport/renderbuffer dimensions. Normal
LC URL launch with SDK 6.0 + Classic Mode shows the menu's Buy Now button in
place and the tutorial's Menu/Reset/Abort controls and instruction panel fully
visible at the correct scale. Full level completion and real-device behavior
remain unverified. LLDB was detached and closed.

Validation: 155 host-side checks pass, covering both private-API paths, native
and guest dispatch, 1×/2×/higher-density displays, external modes, alternate main
modes, and invalid inputs. Eight simulator configurations each pass on iPhone
and iPad (160 checks total), covering SDK 7/11, compatibility on/off, and the
runtime disable switch. The iPad retains its native 2×/1536×2048 metrics. Shared
runtime build and `git diff --check` pass.

Evidence: `/private/tmp/fragger-scale-host-tests.log`,
`/private/tmp/fragger-scale-iphone-tests.log`, `/private/tmp/fragger-scale-ipad-tests.log`,
`/private/tmp/fragger-scale-fixed.lldb.txt`, `/private/tmp/fragger-scale-fixed-menu-2.png`,
and `/private/tmp/fragger-scale-fixed-tutorial.png`.

### Death Rally follow-up — 2026-11-15

Retested the same LegacyStore copy `3341` (1.2) on the iPhone 17 Pro Max
simulator with the original SDK selection (LC's 2.0 fallback). Guest LLDB stopped
at the game's fatal-error routine, `0x488bc`, before its exit-time SIGSEGV at
`0x31b9a`. The actual failure was `File %s not found!` for
`HOME/Death Rally.app/Risoursa/DeathRally.ini`:

- The normal simulator HOME made that path exceed the game's 255-character
  buffer; the attempted filename ended in `DeathRal`.
- An isolated short HOME removed truncation but still failed because the
  executable-named `.app` link was missing. The reserved `LiveExec32.app` link
  alone did not satisfy this game.
- Providing both the short HOME and the named alias passed startup and reached
  the STEER/SHOOT tutorial. No game executable or resource was patched.

`EnsureLegacyBundleLayout` now also creates `HOME/<executable>.app` for unmanaged
pre-iOS-8 layouts, using the same relative-target and collision-preservation
rules as the reserved link. This handles renamed LC installation folders without
game-specific hooks. SDK 8+ and installer-managed standalone layouts are unchanged;
this does not establish standalone support for Death Rally or fix exit cleanup
for unrelated fatal errors.

Regression checks cover spaces, renamed bundles, repeat launches, moved
containers, matching absolute-link migration, conflicting files/directories and
foreign/dangling symlinks. The new checks fail against the previous implementation
and pass with the fix; the existing standalone installer suite passes 72/72.
The host/runtime build passes. A rebuilt-runtime launch with the manual alias
removed automatically recreated it and passed startup into the rendered intro.
It then reached the STEER/SHOOT tutorial and stayed alive beyond 2.5 minutes
without the original fatal error or a new guest crash.
The test uses a short, isolated copy of the data container; original saves are
unchanged. The simulator path limit is worked around for testing, not globally
changed in the runtime.

Classic Mode is enabled in metadata, but normal URL attempts returned to LC's
list in this session. The successful run uses a direct diagnostic launch and
shows a clipped viewport, so it is not orientation/touch validation. Only
simulator controls are used; no Mac keyboard/mouse input or device test.

#### Physical iPhone audio follow-up — 2026-11-18

Retested 1.2 on iPhone 15 Pro Max (`iPhone16,2`), iOS 26.1, original SDK
selection (2.0 fallback) and Classic Mode. An isolated bundle with a fresh data
container uses the current shared runtime already deployed for the SpongeBob
test (SHA-256 `65ce510474e8067eadd4d4d320e55b9c41c5de13248712ff456b425cbac2d080`).

The initial isolated-copy launch failed because its display name had been changed
to `Death Rally (runtime test)`. Guest memory showed a resource path ending in
`Death Rally (runtime test).app/Risoursa/DeathRally.ini`, but the runtime correctly
created the executable-named `Death Rally.app` alias. Restoring the original
`CFBundleDisplayName` in only the test copy resolved this setup failure. The
original save and executable were not modified. The initial exit-cleanup crash
at `0x31b9a` was secondary to the missing resource, not an audio crash.

The corrected launch (PID 7535) reached the intro and a race. Before the OpenAL
fix, the user heard only the soundtrack. Static inspection identified a sound-effects
bridge gap:

- At ARMv7 `0x1a3b8`, the game calls
  `alcGetProcAddress(NULL, "alBufferDataStatic")` (string at `0x971e0`).
- If the returned pointer is null, it skips the PCM buffer upload at `0x1a3d8`
  and proceeds to close the audio file. This is a silent failure path.
- `GuestFrameworks/OpenAL/OpenAL.m` registers the existing guest
  `alBufferDataStatic` adapter in `LC32OpenALLookupALProc`, but
  `alcGetProcAddress` searches only `LC32OpenALLookupALCProc`, which returns null
  for that name. Music uses the separate AudioQueue path.
- Existing `openal_smoke.c` tests static-buffer lookup through `alGetProcAddress`
  only, so they do not cover the lookup used by Death Rally.

The existing guest static-buffer adapter is now exposed through the ALC lookup
too, with no game-specific dispatch or change to the host renderer. The expanded
smoke test fails on the old shim's lookup and passes all 35 checks with the fix,
including buffer replacement through the ALC-returned function pointer. The
31-check streaming regression and 93-symbol export audit also pass. Guest build,
RootFS packing, and aggregate build succeed.

The isolated device runtime received the fixed OpenAL guest binary (SHA-256
`a0c3908e9071ef9ac4c4cfb2b3f84ba5f54101995eb47be62e8a454b2f063705`),
with the previous binary preserved locally. The user confirmed that button-click
sounds played after a fresh launch (PID 7603); race effects were tested after
the orientation fix.
The game also requests the optional `alcMacOSXMixerOutputRate` extension, but
its absence has not been established as a separate audible defect.

**Orientation follow-up:** Death Rally attaches its `GameViewController.view`
directly to the window, without assigning `rootViewController`. Its legacy
rotation policy accepts landscape, but the runtime previously left all direct-
window controllers unrotated, including those accepting UIKit rotation. The
native scene was landscape while the window/controller still reported portrait.
The user also observed landscape Control Center correcting the game on dismissal.

`LegacyRotation.mm` now uses UIKit's existing rotatable-client entry point for
an accepting, registered legacy direct-window controller, preserving the view
hierarchy. Manual controllers returning NO and modern-policy controllers retain
their previous behavior. Initial same-orientation layout gets the same lifecycle
synchronization as explicit roots. When the status bar is still portrait, startup
prefers the scene's valid orientation over the plist's first landscape side.
No dimensions, game identifiers, clipping overrides, or new swizzles were added.

The final native fixture passes six iPhone runs (SDK 2 and 6.1: rootless, manual,
explicit) and three iPad runs (SDK 6.1: rootless, manual, modern-explicit). It checks
initial layout, both accepted turns, nonrepeated callbacks, unchanged manual
renderers, and scene preference over stale launch orientation. Additional
modal/replacement/modern-policy controls passed during development, including
SDK 11. Aggregate build and compatibility-switch compilation pass.

The final shared framework was deployed only to the isolated test runtime
(SHA-256 `e35556957e69a4ffaf02c961be370a7699ce2d34c98d277655d8dfd34ba647cf`).
PID 7889 shows the full landscape garage after one diagnostic native device-
orientation event, with **no injected window/controller/layout changes**. Two
same-process background/resume cycles retain it, with the debugger detached.
This is a menu/layout smoke test, not gameplay touch or race-audio certification.

**Startup limitation in the rotation-only revision (addressed below):** a
face-up cold launch still cropped the game.
Native inspection measured a 640×960 viewport against a 960×640 renderbuffer;
the game's `AppController didRotate` derives this choice from `UIDevice.orientation`
and its own remembered landscape state. With device orientation 5 (face-up) and
no prior landscape event, that state stays zero. A landscape event changes the
viewport to 960×640. That revision handles controller rotation but does
not spoof physical orientation, patch game memory, or override `glViewport`.
Whether this face-up initialization also occurs on original iOS remains untested.
Full orientation validation, including cold launch and both physical landscape
sides, therefore remains open; the earlier upside-down splash is not certified
fixed by these settled-menu checks.

**Landscape animation follow-up:** the user confirmed landscape presentation,
but reported a snap in one direction and an apparent double animation on the
return. An automatically continuing device trace recorded both landscape turns
through `_setRotatableClient:...` with duration zero, once per game window per
turn; `_updateToInterfaceOrientation:duration:force:` was not hit. This establishes
the missing native animation duration, not a duplicated call on the same window.

Actual rootless turns now pass UIKit's `statusBarOrientationAnimationDuration`
(0.3 seconds on the test phone); UIKit itself chooses the half-turn animation.
Startup remains immediate. A repeated same-orientation device notification no
longer forces another client layout. This also closes a separate restart risk,
without claiming that duplicate notifications caused the user's observed effect.
The native fixture now yields to UIKit's asynchronous animation completion:
both sides deliver exactly one will/did pair, the native duration is preserved,
and duplicates during/after a turn cause no additional client call. Six iPhone
runs (SDK 2/6.1, rootless/manual/explicit) and three iPad runs (SDK 6.1,
rootless/manual/modern-explicit) pass. Aggregate build passes.

The animation revision is installed in the same isolated runtime, shared
framework SHA-256
`31dc446552649301fba416fbbe82dcc2dd00888c826743ec357e2ec3b28b49b3`.
The user retested this revision and reports the same snap/double-animation
asymmetry: the duration change does **not** resolve the visual issue.

A supplementary native simulator trace shows one continuous 0.6-second view
transform animation in either direction while the parent transforms stay fixed.
That fixture synthesizes device notifications, not physical scene rotation, so
it does not reproduce or disprove the phone issue. Its rotation assertions pass,
but the injected-dylib diagnostic run fails the minimum-OS and SDK header
assertions and is not a full regression pass. The fixture reads dyld image zero;
insertion changing that image is a possible explanation, not yet verified.
The normal uninjected regression results above remain separate. The face-up
startup and race-audio limitations also remain open.

**Backing-animation correction:** the physical layer recording captures a
concrete error in the rebasing hook. On either landscape turn, its child-layer
animation starts from identity instead of the previously published quarter-turn;
the root simultaneously animates from a temporary quarter-turn back to identity.
The game view itself receives its expected 180-degree, 0.6-second animation.
Thus the hook was exposing UIKit's intermediate portrait-layer configuration as
animation endpoints, even though the final geometry was correct.

The hook now computes/rebases the backing geometry with actions disabled,
restores the previously published root/child geometry inside that transaction,
then applies the final bounds, position and transform under the caller's
original animation policy. No sizes, rotation directions or animation durations
are hardcoded, and clipping and unrelated layer animations are unchanged.
A focused regression catches both incorrect transform starts with the old
implementation and passes with the correction in both directions. It also
checks disabled-actions preservation. Four iPhone SDK 6.1 cases and eight iPad
SDK 6.1/11 cases pass, including ownership/exception, rootless, manual and
explicit/modern-policy controls. Aggregate build and compatibility-switch
compilation pass.

The corrected shared framework is deployed to Death Rally's selected isolated
runtime (the existing `lc32-spongebob-test-20261118.app` test folder), SHA-256
`fde5d2bc38f056881367fc8dbd4b167f61e8d05b05cbfebf0b5ea48eb7c05738`.
The prior framework is retained as `LiveExec32Shared.before-rebase` in the
phone's test staging folder. The user confirms both landscape directions now
animate correctly on the physical iPhone 15 Pro Max. The successful recording
captures six landscape turns: the root stays identity throughout, and the
backing child and game view have matching inverse presentation transforms at
the sampled intermediate times. This removes the temporary quarter-turn
animation seen before the correction. The test process was restarted after
saving the trace to unload the temporary recorder; no debugger remains attached.
This confirms the reported rotation-animation issue, not the separate face-up
cold-launch or race-audio limitations above.

**Initial notification / persistent startup crop:** the legacy startup path now
seeds a single supported presentation orientation from the actual key-window
scene after deferred launch work and initial controller layout have completed.
It does this only for a registered guest window, with device notifications
enabled, when the physical reading is not one of the app's declared supported
orientations. It uses UIKit's native `setOrientation:animated:` notification
path, then restores the physical reading in `@finally`. This is a bounded
startup notification sequence, not a persistent sensor/getter override or a
request to rotate SpringBoard. It adds no swizzle, game identification, viewport
override, fixed dimensions, or guest-memory mutation. SDK 8+ and compatibility-
disabled builds retain their existing behavior.

Native inspection confirmed that UIKit's setter updates the cached device
reading and posts the normal orientation notification; its ambiguity-aware
query still returned face-up on this phone and did not supply a usable initial
landscape orientation. The regression covers face-up, face-down, unknown,
unsupported portrait, already-supported landscape, no device observers,
unregistered controllers, guest-callback safety and repeated startup calls.
All 29 selected runs pass: 16 iPhone SDK 6.1/11 cases, six iPhone SDK 2 cases,
and seven iPad SDK 6.1 cases including existing rotation/backing controls.
Aggregate build and compatibility-switch compilation pass.

The initial-notification revision is installed in the same isolated test
runtime, SHA-256
`30febb44cc45f61070af0f4a6451467b45134e8de89e6650573a178bd49e1ea5`;
the previous framework is backed up as `LiveExec32Shared.before-startup`.
Two untouched cold launches reached a full, uncropped garage without a physical
rotation. On the first, native read-only inspection found device orientation 5
(face-up), scene orientation 3, a 960×640 viewport and a matching 960×640
renderbuffer; the game's remembered landscape state was initialized. The
debugger detached immediately afterwards. An additional launch was backgrounded
during loading and resumed into the full garage. A second background/resume
check after the third launch also retained the full garage in the same process.

**Early loading splash remains intermittent (2026-11-19):** captures roughly seven seconds into
three cold launches showed a complete correctly oriented splash and uncropped
garage, but did not cover the initial transition. The user subsequently reported
a split-second upside-down splash. Independent rapid screenshot recordings
reproduced the wrong-way/clipped transition, including runs where it persisted
through loading. The earlier settled screenshots are not proof of a splash fix.

Synchronized read-only traces and screen recordings then isolated the missing
step. UIKit delivered a landscape scene update about 0.1 seconds after launch,
but its updater did nothing to the rootless window. Both model and presentation
backing stayed portrait through roughly four seconds of synchronous loading;
the scene host meanwhile displayed the rotated surface. Refreshing when the
controller first attaches and flushing at the later guest-startup boundary were
not sufficient. The scene update needed its own matching backing publication.

The existing window-update hook now also refreshes registered rootless backing
while guest startup is pending, and flushes that native geometry before returning
to the loader. It uses the incoming native scene and existing transform math,
without invoking guest rotation callbacks early. Once startup finishes, the old
rootless renderer's rotation ordering and animation policy remain unchanged.

An experimental initial-scene orientation override passed three late screenshots
but failed rapid recording, including a disagreement between the declared first
landscape side and the actual scene. It has been removed: scene settings and
client settings are now left native. Changing idle-observer order and broadening
the refresh gate without early publication also failed. No new hook, image
patch, game-specific check, fixed size, permanent orientation lock or global
clipping override was needed.

Two instrumented experiments and two subsequent clean-runtime cold starts kept
the splash in the same orientation as the garage, without the previously
reproduced wrong-way/clipped loading state. The clean recordings include the
initial transition, not just settled screenshots. A garage background/resume
check retained the full view in the same process. A short native launch animation
is still visible, including transient corner clipping; these captures do not
establish that every animation frame is artifact-free.

The third clean cold start reproduced the wrong-way/clipped splash through
loading again. Early publication fixes a scene update delivered before the
loader, but cannot fix an update that is itself delayed behind loading. The
first-frame issue therefore remains open despite the passing fixture matrix.

An isolated follow-up used UIKit's native orientation fallback (landscape mask
24, provisional portrait, native choice 3) and notified the scene through
`_updateClientSettingsToInterfaceOrientation:withAnimationDuration:`. The client
settings changed immediately, but the local server settings and backing stayed
portrait until loading ended; the wrong splash persisted. Matching the backing
to that requested client orientation removed the prolonged wrong state in one
recording, but exposed sideways/clipped initial frames before the host caught
up. Using UIKit's native animation duration did not remove that transition and
also produced a cropped garage in its recording. These negotiation experiments
are rejected and are not in production source.

The clean early-scene build is installed in the isolated selected runtime,
SHA-256 `f8a1ae8b1371f473876d2c42076c3c238d16dbdc6d4d424bf7578cf584f5f971`.
It supersedes the `7e57dbf2...` native-scene build and the rejected `626d929d...`
scene override. The installed binary was copied back and matched the local
build byte-for-byte. Diagnostic injection was removed afterwards and a fresh
launch returned to the full garage (`early-scene-restored-final.png`); no
debugger or capture process remains active. The early publication change is a
partial fix, not a first-frame completion claim.

All 60 selected native iPhone/iPad regression runs pass across SDK 2, 6.1 and 11
for the early-scene revision. Tests cover unchanged scene-parameter XPC round
trips, initial backing before guest callbacks, early scene publication, deferred
startup publication, face-up initialization, and rootless/manual/modern-policy/
ownership/lifecycle controls. The new regression supplies a no-op native window
updater and keeps the run loop busy: removing early refresh fails both ordering
checks; removing only its flush fails the presentation check. Both negative
controls used isolated source copies. Aggregate GNU make build and compatibility-
switch checks pass. Physical recordings, rather than these fixtures alone,
provide the evidence for the splash improvement.

Evidence: `/private/tmp/lc32-death-rally-phone-20261118.UKVlUY`, including
`crash-state.txt`, `debug-selected-start.log`, `game.asm`,
`original-name-system.log`, `original-name-start.png`, `soundtrack-only.png`,
`openal-{before,after}.log`, `openal-streaming-after.log`, and
`audio-fixed-start.png`, `rootless-client-regression-final.log`,
`ipad-client-regression-final.log`, `final-device-orientation-event.log`, and
`orientation-final-{cold,event,resume1,resume2}.png`,
`rotation-animation-regression-async.log`, and `rotation-animation-ipad-async.log`.
The backing-animation follow-up adds `rotation-layers.log`, `rotation-layers-rebased.log`,
`rebase-animation-baseline.log`, `rebase-animation-regression.log`,
`rebase-animation-ipad.log`, `rebase-animation-build.log`, and
`rebase-animation-switch.log` in the same evidence folder.
Startup evidence: `startup-device-orientation-{api,native}.log`,
`startup-orientation-{iphone-v2,ipad-v2,sdk2,build,switch}.log`,
`startup-orientation-cold1-native.log`, `startup-orientation-cold{1,2,3}.png`,
and `startup-orientation-resume{1,2}.png`. The unsuffixed initial iPhone/iPad
startup fixture attempts omitted the new cases from the executable's allowlist
and are superseded by the `v2` runs.
Splash follow-up evidence: `splash-{transitions,presentation,flush}.log`,
`splash-clean{1,2}.png` (commit-only success/failure),
`splash-final{1,2,3}.png`, `splash-final1-garage.png`,
`splash-final{2,3}-resume.png`, `splash-commit-negative.log`,
`splash-initial-{iphone,ipad}.log`, `splash-final-ipad-scene.log`,
`splash-final-sdk2.log`, `splash-final-build.log`, and `splash-final-switch.log`.
First-frame correction evidence: `lc32-burst{2,3,4,5,6,7,8}/` and matching
timestamp logs, `burst*-contact.jpg`, `initial-backing-negative.log`,
`native-scene-{iphone,ipad}-matrix.log`, `native-scene-switch.log`, and
`native-scene-restored-build.log`. The screenshot helper runs independently of
the game, is bounded to 14 seconds and 256 MiB, and does not attach a debugger.
The first helper attempt stopped at its memory limit; later captures correctly
release each owned screenshot and complete normally.
November 19 evidence adds `first-frame{11,12,13,14,18,19,20}.log`,
`lc32-burst{11,12,13,14,15,16,17,18,19,20}/` with timestamp logs,
`burst{13,15,16}-first-frames.jpg`, `early-scene-resume.png`,
`early-scene-{iphone,ipad}.log`, `early-scene-{iphone,ipad}-lifecycle.log`,
`early-scene-no-{flush,refresh}.log`, `early-scene-gmake-build.log`,
`early-scene-switch.log`, and `native-scene-negotiation.log`.

**Startup scene-readiness race (2026-11-19 follow-up):** the first idle boundary
can occur while the key window's scene still reports unsupported portrait.
The old completion path nevertheless marked startup finished, initialized the
rootless controller using the plist's first landscape side, and consumed the
one-time device-orientation initialization without sending its notification.
A trace caught status/window orientation 4 while the scene was still 1 and
UIKit's active orientation was already 3. A later scene update could therefore
arrive after startup had been incorrectly considered complete.

The existing startup observer now remains pending until a registered guest
key window's scene reports a declared supported orientation. The native finish
entry point checks the same condition. This preserves the existing guest-depth
and due-timer checks; it neither spins a nested run loop nor initializes the
renderer early. No new swizzle, fixed size, sleep, orientation override, or
game-specific condition was added. Native/non-guest windows, sceneless windows,
SDK 8+ and compatibility-disabled builds retain their previous behavior.

All 48 selected iPhone/iPad fixture runs pass across SDK 2, 6.1 and 11, including
the new unsupported-scene/late-initialization case and the existing startup,
rootless, manual, modern-policy, ownership and lifecycle controls. An isolated
negative-control source copy without the finish guard fails the new regression.
The aggregate build, compatibility-switch checks and `git diff --check` pass.

**Result on the November 19 build:** the early splash was still intermittent. The read-only recording of this
revision received its scene update before loading and looked correct. A clean,
uninstrumented cold launch (`lc32-burst25`) still showed the rotated/clipped
splash through loading, although its garage recovered to full size. The next
clean capture (`lc32-burst30`) showed a correctly oriented splash and garage;
background/resume retained the same process and full garage. These mixed
results do not establish a first-frame fix.

The clean shared framework is installed in the selected isolated runtime and
was copied back for SHA-256 verification:
`ef384d1d00c866c8a7e4e13dbac9dd42a734999e821b3e7972322a4e94074baa`.
It supersedes the earlier `f8a1ae8b...` build. No debugger or injected recorder
remains active.

Additional experiments remain outside production: UIApplication's animation
fence synchronization returned immediately (`didSpin=0`); on this OS its native
provider is `_UISimpleFenceProvider`, not a pending-scene-update drain. Its
use did not repair the splash. Active-orientation backing fallbacks at launch
or the first idle boundary were also not adopted: their successful captures
already had a supported scene, so they did not establish the proposed fallback's
effect on the failing branch. UIWindow's drawing-fence APIs were inspected,
but no cross-process fence or scene-setting override was added.

Evidence in the same folder: `startup-scene-ready-{build,switch,iphone,
iphone-controls,ipad,negative}.log`, `first-frame-sync21.log`,
`first-frame-active22.log`, `first-frame{23,24}.log`, `idle-frame{26,27,28,29}.log`,
`lc32-burst{21,22,23,24,25,26,27,28,29,30}/`, `burst*-contact.jpg`,
`native-{scene-fences,first-frame-sync,fence-callback,drawing-fence,
initial-orientation,fence-provider,drawing-symbols,window-drawing-fence}.log`,
and `scene-ready-resume*.png`.

**Death Rally cold-start follow-up (2026-11-20, physical iPhone 15 Pro Max):**
The blocking load runs in the first `-[AppController update]`, called by Quartz
Core's display-link dispatcher. The next main-thread guest callback was 4.06
seconds later. If UIKit was still presenting the provisional portrait scene,
the sideways, clipped splash could remain onscreen throughout that interval.
Merely requesting a supported scene earlier still failed on 3 of 10 starts.

The shared runtime now lets a guest display link created against unsupported
startup geometry yield until the first supported refresh has had a chance to
commit. The wait is bounded by UIKit's orientation animation duration; links
created for a ready scene, native callers and later game frames run normally.
That change removed the prolonged wrong orientation, but all six recordings of
the display-link-only control still showed cut corners at the handoff.

While the initial guest backing turns, Core Animation holds the presentation
of that backing layer until the turn settles. It does not hide the guest
window, change model opacity, touch coordinates or clipping, or guess a
landscape side. If UIKit replaces the layer it inherits only the remaining
hold; the hold expires without requiring another callback from the game.
An already-supported first scene and subsequent rotations do not acquire a
new hold. Disabling the window's native rotation animation did not achieve this
and is not part of the fix.

On the final uninstrumented build, **8/8 separate cold launches** on the
iPhone 15 Pro Max showed the complete, upright splash from its first captured
appearance through loading. All eight reached the full garage; one subsequent
background/resume retained the same process and garage layout. The installed
isolated framework matched the build byte-for-byte (SHA-256
`5dd206fdcd62760d6e049ac5b2f335ad4cbd444eaaba1adf55e46707ea30a550`).
The iPhone/iPad simulator controls passed 42/42 across SDK 2, 6.1 and 11;
both UIKit compatibility build modes passed. Compact local evidence:
`tmp/death-rally-splash-20261120/verified-launches.jpg` (opening frames,
mid-load and settled garage for every run), `corners-nov20-final-3.jpg`
(display-link-only control), and `verified-*.log`.

**Race audio retest (2026-11-20):** On the physical iPhone 15 Pro Max, the user
heard both the engine rev while accelerating and gunfire while shooting, over
the soundtrack during a race. The running copy used the verified orientation
build and the fixed guest OpenAL shim identified above.

## Skipped because the issue supplies another download source

Update September 26: the user requested a fresh search through the approved
catalogs. See the [approved-source audit](skipped-game-sources-2026-09-26.md)
for newly eligible copies and the Cling Thing version mismatch. The exclusions
below describe the original September 18 pass, not current source availability.

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

### Cling Thing 1.2 — score reporting follow-up, 2026-11-15

The missing `GKScore` property bridges left the native score's `valueSet`
flag false even after the game assigned a score. The shared GameKit template
now forwards these accessors, alongside the same missing-property pattern in
12 other GameKit classes. Local ARM32 simulator regressions pass 117 property
checks plus the existing 13 achievement checks without contacting Game Center.

The subsequent `LiveContainer-2026-11-15-172200.ips` crash still used the
isolated October 3 runtime selected for this game, not the rebuilt framework.
Its loaded framework UUID matched that older runtime, whose `GKScore.value`
still read and wrote guest-only storage. After cold-launching with the current
runtime, Cling Thing 1.2 (build 65), Legacy SDK 7.0 + Classic Mode, completed
level 1-1 and advanced to level 1-2 on the iPhone 17 Pro Max simulator.
LLDB observed `value = 273` and `valueSet = 1` for both the chapter and overall
leaderboard submissions, with no exception. This validates the completion
path, not successful online leaderboard delivery or device behavior.
The original save container and SDK/Classic Mode settings were retained.

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

**November 15 retest:** the existing LegacyStore 1.0 bundle still crashes before
the menu with the current shared runtime (`b0d79e7`). Two normal LC URL launches
reproduced the startup failure. Classic Mode and the existing legacy SDK setting
(`131072`) were retained; this executable has no SDK-version load command, while
its build metadata names `iphoneos4.0`. Only its runtime selection was changed
to `lc32-forlorn-20261114.app`, with the previous metadata backed up.

A debugger-only argument launch captured the same guest `MemoryRead32(0)` at
`pc=0x73dd8`, `lr=0x6c7f0`. Native `alcGetCurrentContext()` was NULL and the
game's ALmixer error pool still contained `Couldn't generate sources: Invalid
Operation`. The normal-launch crash report's shared-framework UUID matches the
current runtime, ruling out the stale-runtime problem seen with Cling Thing.
No runtime or game patch was made, gameplay remains blocked, and device behavior
is still untested. LLDB was detached and closed. Evidence and metadata backup:
`/private/tmp/lc32-bubble-retest.XWTVtT/`; normal-launch crash report:
`LiveContainer-2026-11-15-191000.ips`.

**Simulator fallback fixed:** `SilentContext.h` supplies AL source, buffer,
listener and error state while the existing native ALC handles remain inactive.
Playback advances on a monotonic clock, including pitch, offsets, pause,
looping, suspend/resume, streaming FIFO processing, and natural completion.
Buffers are shared per device; sources/listeners/errors are context-local.
Attached buffers cannot be deleted or refilled. Operations serialize across
guest threads; PCM is validated in bounded chunks and is not retained by the
null renderer. It produces no audio and is not a spatial mixer. Queue/error
behavior follows the core [OpenAL programming guide](https://www.openal.org/documentation/OpenAL_Programmers_Guide.pdf).

The fallback is selected only in Simulator, including the retagged iPhoneOS
host framework used by LC; `LC32_OPENAL_SILENT_CONTEXT=0` remains a diagnostic
opt-out. Setting that environment variable on a physical device no longer
forces the simulator path. Normal device dispatch still uses native OpenAL.
The audio fix changes no guest shim, game binary, SDK setting, or orientation hook.

Validation:

- The existing `openal-smoke` fails source allocation with `0xa004` on the old
  runtime and passes on the new one. All 93 guest exports pass the symbol audit.
- New `openal-streaming`: 31 checks, zero failures, including FIFO completion,
  pause/loop/suspend behavior, offset conversions and stopped-source seeking,
  attached-buffer protection, atomic invalid batches, sticky errors, context
  isolation, stale handles, and cleanup. Both suites pass on the final deployment.
- Normal LC URL launch reaches Bubble Ball's menu. A portrait-origin run became
  clipped after rotation; cold-launching in landscape restores the expected
  presentation. That separate rotation behavior was not patched here.
- In the landscape launch, level selection and tutorial dismissal respond;
  dragging the triangle and pressing Start completes level 1. The success dialog
  appears, and Next Level opens level 2 without a crash. This is a short gameplay
  test, not an all-level or physical-device certification.

Build/test logs and screenshots are in the same `lc32-bubble-retest.XWTVtT`
evidence directory, including `physics-result.png` and `level-two-ready.png`.

**Legacy alert orientation fixed:** the scene and alert controller already
reported landscape, but UIKit's `UIAlertView` shim window remained 320×480.
Only its root view rotated; the modern alert presentation container was a
window-level sibling and inherited the portrait bounds. `LegacyAlerts.mm` now
opts `_UIAlertControllerShimPresenterWindow` into its native
`+_transformLayerRotationsAreEnabled` policy. This is a subclass-only policy
override, not a game-specific transform, forced frame, or orientation mask.
It uses the existing legacy-SDK gate and native method validation.

The rebuilt shared runtime was cold-launched through LC on the iPhone simulator.
The tutorial and repeated pause alerts are centered and fully visible; Let's
Play, Resume, and Select Level respond at their displayed positions. LLDB
confirms the alert window and presentation container are 480×320 while the
game window stays 320×480. The alert-window class policy is YES and the base
UIWindow policy remains NO. The existing lower gameplay-area clipping is also
visible in the pre-fix `tutorial-dismissed.png`; this alert correction does not
resolve it. Physical devices and older UIKit versions have not been retested.
Evidence: `alert-tutorial-fixed.png`, `alert-reopened-fixed.png`, and
`alert-host-build.log` in the same directory. Debugger detached and closed.

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

**Gameplay and resume follow-up — 2026-11-17:** rebuilt the current shared
runtime at `6eb3695` and deployed it to `lc32-forlorn-20261114.app` on the
iPhone 17 Pro Max/iOS 27 simulator. The existing 1.1.2 installation and save
container were retained. Backed up LC metadata, selected that runtime, and
corrected the stale SDK 2.0 override to the executable's original SDK 6.1
(`393472`); Classic Mode remains enabled. Testing used normal LC URL cold
launches and idb simulator input, without Mac keyboard/mouse interaction.

Completed the first level in each of the four categories: sliding blocks,
symbol placement, box-pushing, and sliding wire tiles. Each returned to the
vault with its completion checkmark and increased progress. Moving pieces,
placing symbols, robot pathfinding/pushing, and wire-tile dragging all worked.
Subsequent cold launch restored centered presentation and retained all four
completion checkmarks. No new game crash or missing bridge reproduced. This
is a first-level smoke pass across the four engines, not full-game completion.

The old resume-layout issue still reproduces. In the initial gameplay cycle,
the same process (`2597`) retained its moved block after background/resume,
but the 320×568 canvas shrank into the upper-left corner. Touches at its new
visible positions still worked, including completing the puzzle. A later
process (`4456`) survived multiple background/foreground transitions, including
return through the simulator Home screen's LC icon. Later presentation also
shifted after explicit Classic reactivation; the resume path is not a layout
pass even though gameplay continued. Cold relaunch restores the normal view.

Native inspection separates this from game layout: cold launch's scene
settings contain a 320×568 display configuration/frame, while icon resume's
settings contain 440×956. The client still reports
`compatibilityMode = scaledZoomedOut`. The window and backing layers initially
remain 320×568; saving/restoring just those dimensions would not restore the
host's presentation. Reissuing `__ActivateAsClassic = 2` did not cleanly restore
the original result.

An isolated native UIKit control, with **no LiveExec32 or LiveContainer hooks**,
reproduces the same shrink when a modern-host bundle (SDK 26, `UILaunchScreen`)
is launched with that forced-Classic option and resumed. The SDK 6.1 variant's
naturally classic presentation stays centered. This establishes a forced-Classic
scene-hosting failure on this simulator independent of the guest bridge; it
does not establish behavior on a real device or every iOS version. No runtime
geometry workaround was added. The remaining resume issue requires further
Classic Mode/scene-hosting work, not another `NSValue` repair.

The temporary probe app was uninstalled; its source, build script, logs, and
screenshots were retained under `/private/tmp/heist-retest-20261117/`. The
initial SDK-27 probe hit UIKit's scene-lifecycle requirement before testing;
that diagnostic crash is unrelated to The Heist. All task debugger sessions
were detached/closed (one stalled background-probe inspection was stopped
with the disposable probe). The game was left running after a normal cold
launch. Runtime build and diff checks pass; no production code change was
needed for the gameplay checks. Real-device testing remains outstanding.

Evidence in that directory: `level1-complete.png`, `puzzle2-complete.png`,
`puzzle3-complete.png`, `puzzle4-complete.png`, `cold-saved.png`,
`saved-category-1.png`, `saved-symbols.png`, `saved-confirmed-3.png`,
`saved-confirmed-4.png`, `resume1.png`, `icon-resume.png`,
`cold-settings.log`, `resume-settings.log`, and the `native61-*`/`native26-*`
control screenshots. Build log: `/private/tmp/heist-latest-build.log`.

**Forced-Classic resume investigation — 2026-11-17:** traced the native
control's activation in simulator SpringBoard. On ordinary resume,
`SBDeviceApplicationSceneHandle`'s
`_modifyProcessExecutionContext:fromRequestContext:entity:` reads activation
setting 20 (the explicit Classic override), falls back to the installed app's
`_defaultClassicMode` when it is absent, and calls
`-[SBApplication _setCurrentClassicMode:]`. The modern host's current mode
changes from 2 to its default 0. The launch override is also exported as
`CLASSIC_OVERRIDE`; it does not make subsequent ordinary activations retain
that selection. This accounts for a Classic client canvas losing its host
presentation without a guest crash.

A temporary debugger intervention, restricted to the disposable native probe,
preserved mode 2 at that setter. The same process then resumed with its
original centered/scaled presentation. The breakpoint was removed and
SpringBoard detached; no system hook or persistent system modification was
installed. This establishes the host-side cause on this simulator, not a
non-jailbreak runtime fix or a result on other iOS versions.

App-side experiments did **not** produce a complete repair:

- Reopening the running app with `__ActivateAsClassic = 2`, including a
  one-second delayed self-reactivation, did not restore the original native
  geometry. The native-only control also fails this test.
- A client display-configuration request did not restore the Classic viewport.
  Direct `FBSScene updateSettings:` mutation traps in the native control;
  those scene settings are host-owned, not an app-owned repair interface.
- Scaling/centering the game's outer layers produced the expected native
  point conversions, but rendering remained clipped to the scene's 320×568
  extent. The layer chain had no `masksToBounds` clipping. This is why saving
  window size/scale and restoring those alone is insufficient. The measured
  device-specific numbers were diagnostic only and were not added to LC32.
- `_UISceneClassicModeExternalSettingsModifier` rewrites display/frame settings,
  but an app-process breakpoint on its updater had zero hits during the native
  resume test; it did not provide a verified app-side hook point.

There **is** a non-jailbreak packaging route in the native control. Keeping its
Mach-O SDK at 26, removing `UILaunchScreen`, and supplying no modern launch
metadata selects natural 320×480 Classic presentation. Adding the installed
Heist's `Default-568h@2x.png` selects 320×568 instead. Both retained their
centered presentation after ordinary background/resume. For the 568-point
case, process 26184 retained the same scene/session, screen and window bounds;
`CLASSIC_OVERRIDE` was null. Thus the successful natural-Classic control does
not require downgrading the host's SDK.

This is an installed-host-bundle choice, not a per-game runtime setting.
LiveContainer declares a launch storyboard and modern launch-image sizes;
changing those would also affect its frontend and other guests. Its bundle
metadata was left unchanged. A dedicated Classic host/packaging variant is a
possible next experiment, but was not implemented or game-tested here.
Standalone packaging retains the game's metadata; actual standalone resume
behavior still needs testing. The current per-game forced-Classic resume issue
therefore remains unresolved. Real-device validation is also outstanding.

Evidence: `/private/tmp/classic-resume-20261117/`, notably `fixed-before.png`,
`fixed-after.png`, `delayed-after.png`, `compositor-compiled.png`,
`compositor-describe.log`, `heist-current-settings.log`,
`native26-no-launchscreen-resume-settled.png`, and the `native26-568-*`
screenshots/geometry logs. Probe sources remain under that directory and
`/private/tmp/heist-retest-20261117/`. Diagnostic transforms were removed by
cold-restarting The Heist; task debuggers were detached and the native probe
uninstalled. No production runtime change was made in this investigation.

**Saved-window prototype follow-up — 2026-11-17:** tested the proposed
save/restore approach directly, separately from the installed-bundle route.
There is now a working app-side prototype on the iPhone simulator, including
The Heist gameplay. At this stage it was **not enabled in the shared runtime**;
the integration follow-up below supersedes that limitation.

The baseline captures the actual window's bounds, center, affine transform,
content scale and scene bounds during the cold forced-Classic launch. UIKit's
private `_isClassic` returns false for the modern-SDK forced-Classic control,
so that query alone incorrectly skipped capture; the diagnostic uses the
explicit positive `CLASSIC_OVERRIDE` launch marker. This is a cold-launch
capture, not a claim that the environment variable proves Classic is still
active later. Replaying only the saved window values cannot restore the lost
external scale: those values can remain unchanged while the canvas visibly
shrinks, and the scene may still expose a stale 320×568 rendering boundary.

The successful experiment first requests ordinary host presentation with
`__ActivateAsClassic = 0` **inside the app**, retaining the same process.
This clears the stale scene boundary. It then restores the saved logical
window bounds/content scale, composes the saved transform with a uniform fit
from the captured scene into the current scene, and maps the saved center
into that viewport. No phone dimensions or aspect ratio appear in the
restoration calculation. This does not restore SpringBoard's Classic flag;
it reproduces the saved canvas inside a normal host scene.

Results:

- Native 320×568 control: two automatic resume cycles retained its presentation;
  the same physical button coordinate incremented a counter from 1 to 2 to 3.
- Native 768×1024 logical-window control, already scaled inside the Classic
  scene: retained its 3:4 rectangle and existing transform after resume; the
  same physical button coordinate incremented the counter from 1 to 2.
  This is a synthetic 3:4 window test on iPhone, not an iPad-device/game pass.
- The Heist initially overwrote the restored frame later in foreground layout.
  A breakpoint identified `-[UIWindow _configureRootLayer:sceneTransformLayer:
  transformLayer:]`, through LC32's existing legacy-rotation hook, resetting
  the frame during `_updateTransformLayer` calls from scene metrics and system
  snapshots. Synchronous restoration inside this update also left footer
  content missing. Coalescing restoration onto the main queue **after those
  transform updates**, with a reentrancy guard, preserved the complete layout
  without a timed delay or child-view rewrites.
- With that temporary diagnostic library in process 35309, ordinary resume
  restored the vault and footer automatically. A footer tap opened the puzzle
  selector; selecting the previously completed first sliding-block puzzle
  worked. A drag moved the bottom-left block one cell right. A second ordinary
  resume retained the process, board and moved block; dragging at the original
  screen coordinates moved it back. No new crash reproduced.

The successful library is `window-save-probe.m` / `window-save-probe.dylib`
under `/private/tmp/classic-resume-20261117/`; it was loaded only into the
test process. Evidence includes `auto-resume*.png`,
`auto-three-four-{cold,resume}.png`, `heist-window-save-install3.log`,
`heist-window-save-auto3.png`, `heist-window-save-category-settled.png`,
`heist-window-save-{gameplay,moved,gameplay-resume,moved-back}.png`.
Earlier `auto2` game captures are the incomplete synchronous variant, not a
passing result. The temporary native app was uninstalled and the game was
cold-restarted to remove the injected hooks after testing.

At the prototype stage, production integration remained unimplemented. It had
to avoid treating a stale
launch marker as current host state, preserve the exact saved presentation
when native Classic zoom differs from aspect-fit, and handle rotation,
multiple/native overlay windows, guest screen-metric queries and affected
iOS versions. Landscape games, real iPad behavior, native alerts and devices
have not been validated with this fallback. The prototype establishes that
saved-window restoration is viable; it is not yet a general compatibility fix.

**Shared-runtime integration — 2026-11-17:** added `ClassicPresentation.mm` to
`LiveExec32Shared`, behind `LC32_UIKIT_COMPATIBILITY`. A positive
`CLASSIC_OVERRIDE` only enables observation. Capture additionally requires a
live `sceneFrameInKeyboardReferenceSpace` that uniformly maps the logical
fixed-screen bounds into a distinct host rectangle. The environment marker
alone cannot trigger restoration. Only guest-owned main-screen windows are
captured; native overlay windows are not resized.

The snapshot retains window bounds, center, transform, layer scale, parent
extent, actual Classic zoom, scene bounds, and guest screen metrics. Restoration
composes that saved geometry into the physical parent with a uniform scale;
there are no device resolutions, game identifiers, or fixed aspect ratios in
the implementation. The app-side activation request still clears the stale
host clipping boundary without restarting the process. This recreates the
logical Classic canvas; it does not repair SpringBoard's Classic flag.

Guest scale and mode pixels are captured through the existing adapters, not
reconstructed from native screen scale: older UIKit can expose a different
application scale through its caller-sensitive mode API. Regression coverage
includes restoring a captured 1x application on a 3x native screen.

There is one new native swizzle, `UIWindow._updateTransformLayer`. Restores are
coalesced onto the main queue after UIKit's compositor updates. During those
updates and restoration, the window's autoresizing is temporarily suppressed
and then restored: intermediate physical bounds must not resize logical child
views. Existing guest screen adapters and the existing legacy application-frame
hook use the same snapshot. Native public UIScreen getters remain physical, so the
outer compositor can cover the real scene.

Landscape testing caught and fixed two integration errors: Doodle Truck 2's
controller rotation initially sized its renderer from the physical screen,
and Fragger's autoresizing root subsequently applied the window-size delta
a second time. No renderer-specific hook or child-view geometry replay was
added. The temporary extra reference-frame experiment was removed.

On the iPhone 17 Pro Max / iOS 27 simulator, using original SDK + Classic Mode:

| Game | Shared-runtime resume result |
| --- | --- |
| Doodle Truck 2 1.1.3 (SDK 6.0) | Two same-process resumes and both landscape directions retained proportions; menu/world/level selection, tutorial dismissal, and in-game Resume worked. |
| Fragger DS 1.11.4 (SDK 6.0) | Two same-process resumes during gameplay and rotations in both directions retained the full level. Throwing consumed a grenade (6 → 5); Pause opened at the expected coordinate afterward. |
| Cling Thing 1.2 (SDK 7.0) | Two same-process resumes and both landscape directions stayed upright and fully visible. Gameplay input reached level completion; Next opened level two. |
| The Heist 1.1.2 (SDK 6.1, portrait regression) | The final shared build retained the entire vault/footer after resume; tapping the original footer coordinate opened its puzzle selector. |

Shared-framework build, geometry regression (including synthetic 3:4 and
rotated transforms), screen-metric matrix, and compatibility-off/on compilation
checks pass. The isolated native rotation fixture also builds for SDK 2, 5,
6.1, 7, 8, and 11 (build-only, not an iPad or SDK 11 gameplay pass).
Game checks used the selected shared runtime, not an injected
diagnostic library. Evidence is under `/private/tmp/classic-resume-20261117/`:
`doodle2-layout-*`, `fragger-stable-*`, `cling-integrated-*`,
`heist-captured-metrics-*`, `regressions-final.log`, `legacy-rotation-build.log`,
and `geometry-final.log`. Earlier failed experiment
captures are not passing results.

After refining capture to retain effective guest scale directly, The Heist's
resume/footer interaction and Cling Thing's menu resume/opposite-landscape
rotation were repeated on that exact final build (`cling-captured-metrics-*`).

The restored canvas is centered in the ordinary physical scene; the former
sideways system status bar disappears, and vertical placement differs slightly
from the forced-Classic baseline. No stretching or bottom clipping remained
in these passes. iPad testing was explicitly deferred. Real devices, older
iOS versions, native alert/keyboard presentation, and a full SDK 11 matrix
remain unverified; these are smoke tests, not full-game completion claims.

**iPad simulator follow-up — 2026-11-17 (`f170004`):** tested the committed
shared runtime on iPad (A16), iOS 27, device
`3FB9DBF4-A92A-469B-B2AB-66589F29AE2D`, with LiveContainer 3.8.10. This
supersedes the deferred-iPad note above. **The iPad result is not a full pass.**
No runtime source changes or debugger-injected repairs were made in this pass.

Reused the iPhone installations through resource symlinks, with separate
`Info.plist`/`LCAppInfo.plist` files and cloned saves under fresh iPad container
UUIDs. The iPhone metadata and saves were not used as writable test state.
Cleared the copied Classic-mode cache so LC could choose the iPad policy.
Classic Mode stayed enabled; SDK overrides were original 6.0/6.1/7.0 for the
three landscape games and The Heist. Flight Control HD is **1.07**, minimum
iOS **3.2**, with no SDK field in its Mach-O; it used the established original
SDK fallback `0x20000`, not a fabricated SDK inferred from its minimum OS.
All interaction used idb/simctl, without Mac keyboard/mouse input.

| Game | Cold launch | Resume / rotation result |
| --- | --- | --- |
| Doodle Truck 2 1.1.3 | Sideways and distorted in landscape. The pre-integration runtime reproduces the same cold layout. | Two resumes retain PID 75675, but the visible canvas changes proportions/placement. Opposite landscape remains sideways. Not a visual pass. |
| Fragger DS 1.11.4 | Sideways in landscape; the pre-integration runtime reproduces it. | Two resumes retain PID 77448. The canvas becomes narrower/taller and remains sideways in both landscape directions. Not a visual pass. |
| Cling Thing 1.2 | Sideways in landscape; the pre-integration runtime reproduces it. | Two resumes retain PID 78415, with changed canvas proportions and persistent sideways presentation in both landscape directions. Not a visual pass. |
| The Heist 1.1.2 | Correct centered portrait vault and footer. | Three resumes retain PID 79617 and centered logical geometry. The original footer coordinate opens the puzzle selector. However, footer/progress-strip rendering disappears intermittently after resume, including a capture after a 15-second wait; it also repainted without relaunch. Partial success, not a clean visual pass. |
| Flight Control HD 1.07 | Correct centered 4:3 portrait menu. | Portrait resume retains the canvas. Landscape rotation produces sideways/misarranged panels, which remain incorrect through further resumes; returning to portrait retains the wrong panel arrangement. PID 81634 survives all three cycles. Menu-only test: Play taps did not establish gameplay, including before the first resume. |

No resume crash occurred in these tests. The landscape menu taps were not
sufficient to establish gameplay/input correctness; a running process is not
counted as a successful game/layout pass. Flight Control's native-iPad rotation
problem was also recorded in the earlier
[`sheep-flight-original-sdk-2026-09-28.md`](sheep-flight-original-sdk-2026-09-28.md)
investigation; this pass did not bisect intervening changes.

Read-only debugger evidence rules out a simple missing capture or 16:9-only
snapshot in Doodle Truck: cold `CLASSIC_OVERRIDE` is `14`, and the saved window,
parent, and screen bounds are **768×1024**, with **1536×2048** guest pixels at
**2×** and a measured presentation zoom of **1.0677083**. Before background,
`normalized` is false. After resume it is true, activation is complete, and
the window still has the saved logical bounds with the uniform transform.
Its visible landscape result is nevertheless wrong. The iPad scene/backing
composition needs further investigation; merely storing another fixed size
would not address this evidence.

The Heist's resumed native root remains **320×568**; the window frame is
`(90,22;640,1136)` with a **2×** transform inside the native **820×1180** scene.
Its footer/progress views remain present in the hierarchy at their logical
positions. That distinguishes its intermittent missing pixels from losing
the saved canvas or restarting the game, but does not establish the redraw
failure's root cause.

**The Heist redraw audit and correction — 2026-11-17:** the earlier
screenshot-based claims of intermittent footer loss, including the iPad table
above and the alleged native-clipping/physical-iPhone reproductions, are not
supported by a subsequent audit of the saved PNG pixels. Displayed previews
were interpreted as losing static content, but the corresponding original
full-resolution files retain it. Those visual interpretations must not be used
as evidence of a native compositor defect or as justification for a new hook.
The cause of the preview discrepancy itself is not established.

A clean launch of The Heist 1.1.2 on the iPad A16 / iOS 27 simulator, original
SDK + Classic Mode, passed three same-process resume cycles (PID 40273).
Six screenshots per cycle, spaced approximately two seconds apart, were
compared against the cold frame. All **18 frames** have **zero pixel difference**
in the progress/settings strip and the separator above it. These comparisons
use original PNGs, not resized previews. Native inspection confirms restored
320×568 bounds, a uniform 2× transform, `normalized=true`, no pending
activation, and **21 layers still using `masksToBounds`**, including the game
root. Window/root `shouldRasterize` is false. A footer press at the original
coordinate opens the puzzle selector after the third resume. This is a
sampled menu/resume/input pass, not full-game or continuous-frame coverage.

The earlier physical iPhone 15 Pro Max / iOS 26.1 captures were audited too:
the progress/settings strip and separator match the cold frame exactly in all
five saved resume screenshots. The isolated game/runtime installation and
same-process resumes remain valid observations; the claim that these files
prove a device clipping failure is withdrawn. No new phone test was performed
during this audit. The previous window-rasterization experiment also has an
identical footer in all three files, so its apparent visual failure was not
valid evidence. Neither rasterization nor any clipping override is retained.
The broader native-control conclusions likewise need pixel-verified evidence
before being treated as reproductions.

A separate, verified guest `CATransform3DMakeRotation` defect remains fixed:
the old matrix had incorrect sine signs and a cosine in one off-diagonal
term. `test/quartzcore_transform.c` covers signed axes, a non-unit axis,
orthonormality, determinant, and the zero axis. It fails against the old guest
implementation and passes with the corrected matrix on iPad and iPhone
simulators; the native macOS reference passes too. This is a mathematical
compatibility fix, **not a demonstrated fix for footer clipping**.

All temporary debugger mutations were discarded before the clean pass; no
production clipping, rasterization, or per-frame redraw policy was added.
Evidence is in `/private/tmp/classic-ipad-resume-20261117/`:
`pixel-resume-check.sh`, `heist-pixel-baseline-cold.png`,
`heist-pixel-resume-*.png`, `heist-pixel-clean-state.log`,
`heist-pixel-puzzle-selector.png`, `audit-heist-captures.py`, and
`pixel-audit.json`. Original phone files remain under
`/private/tmp/heist-iphone15.KUS1Hi/`. Future redraw reports should establish
missing pixels in raw captures before changing native clipping behavior.

**Rotation-matrix game retest — 2026-11-17 (`b2fe48d`):** tested Doodle Truck 2
1.1.3 (original SDK 6.0) and Cling Thing 1.2 (original SDK 7.0), with Classic
Mode enabled, on the iPhone 17 Pro Max and iPad A16 simulators, both iOS 27.
Both installations select the same shared runtime and repository RootFS;
the corrected guest QuartzCore SHA-256 is
`ac354b80bba084147615541a5e8a24ec48f3227f7d6d60900530ae84ba2d8500`.
No runtime source changes, clipping overrides, or debugger-injected repairs
were made during this retest. Interaction used idb/simctl only.

Each main test includes a cold launch in Landscape Left, a same-orientation
background/resume, rotation to Landscape Right followed by another resume,
and a third resume inside the first-level tutorial/game. Original full-size
screenshots, comparison contact sheets, and read-only native geometry checks
were used together; preview-only disappearance is not treated as a failure.

| Game / simulator | Rotation and resume result | Input / game depth |
| --- | --- | --- |
| Doodle Truck 2 / iPhone | Upright through all three resumes; PID 45376 retained. | Play, world selection, and level selection respond; first-level tutorial survives resume. |
| Doodle Truck 2 / iPad | Upright through all three resumes; PID 45374 retained. | Play, world selection, and level selection respond; first-level tutorial survives resume. |
| Cling Thing / iPhone | Upright through all three resumes; PID 47705 retained. | Enters level 1, resumes, accepts input, and reaches the level-results screen without a crash. |
| Cling Thing / iPad | Upright through all three resumes; PID 47704 retained. | Enters level 1, resumes, and a held ceiling touch visibly lifts the character; level completion not tested. |

Both games retain logical window bounds of 320×568 on iPhone and 768×1024 on
iPad. After Classic normalization, the measured window scales are uniform
(1.29375 and 1.06770833 respectively); the backing view rotates in the opposite
direction when the landscape orientation changes. The iPhone canvas shifts
slightly when the old sideways status bar disappears. No nonuniform stretching
or upside-down result was observed in the settled captures.

**Visual caveat:** Doodle's iPhone first-level scenery extends beyond the
central background artwork into the side margins. A separate fresh launch
(PID 50265), before any background/resume, shows the same behavior. This is
not a demonstrated resume regression; no pre-matrix-fix comparison was made
for that scenery, so its relationship to the matrix fix is unestablished.
These are scoped orientation/resume smoke tests, not full-game certification
or physical-device results.

Evidence: `/private/tmp/lc32-rotation-retest-20261117.rr1SBI/`, including
`test.sh`, `*-cold.png`, `*-resume-left.png`, `*-resume-right.png`,
`*-state.log`, `*-doodle-tutorial-resume.png`, `*-cling-level1-*.png`,
`iphone-doodle-fresh-tutorial-no-resume.png`, and the comparison contact sheets.

The baseline comparison used an isolated runtime copy with the saved
pre-integration shared framework and the same guest RootFS. Doodle Truck's
old-runtime resume also changes presentation, so neither its old nor new
iPad resume is a visual pass. All three compared games' iPad metadata was
restored to select the current runtime afterward. The current shared binary
remained unchanged throughout (SHA-256
`9d432dd37fa3c1d80bea30ea8d0d9ce2b9227cefc9949dc1a18ee9d6ffbb48cb`).

Evidence and reproducible launch/screenshot helpers are under
`/private/tmp/classic-ipad-resume-20261117/`: `setup.sh`, `test.sh`,
`*-cold*`, `*-resume*`, `*-baseline-cold*`, `heist-settled.png`,
`doodle-{cold,resume}-geometry.log`, and `heist-resume-geometry.log`.
Real-device iPadOS and SDK 11 gameplay remain untested. The iPhone validation
above still stands; it must not be generalized to an iPad compatibility claim.

**iPad landscape repair — 2026-11-17:** the shared runtime now expresses the
legacy backing rotation below the CAContext root-layer boundary. A native
diagnostic label rotated incorrectly alongside Doodle Truck's GL content;
changing only the root layer's transform did not change the iPad output.
Disabling the legacy backing hook or enabling UIKit's modern transform policy
did not fix it. These debugger experiments were discarded before cold retests.

The existing `LegacyRotation.mm` configuration hook now publishes an identity-
transform root with its measured frame, and composes the original transform
and position into the existing scene child. Window/renderer logical coordinates
are unchanged. There are no new swizzles, iPad/game-name checks, fixed canvas
sizes, or invented rotation angles. The existing SDK/guest-controller scope
and exception-safe restoration of the temporary ownership policy remain intact.

`ClassicPresentation.mm` also detects verified Classic loss without requiring
a prior background event. An ordinary `simctl launch` of the already-foreground
Flight Control process reproduced that case: PID 4801 stayed alive, `backgrounded`
remained false, and restoration finished with `normalized=true`, no pending
activation, and the original logical canvas at its measured uniform zoom.
This reuses the existing metadata checks, saved state, and activation path;
it does not force normalization solely because a rotation occurred. A stricter
experimental check against `UIScreen.fixedCoordinateSpace.bounds` was rejected:
after Classic loss, UIKit can retain all its old screen metrics (including
`nativeBounds`) while the host rectangle has already changed. Requiring equality
prevented restoration until another rotation. The existing measured-mapping
detection is retained instead, without introducing physical-size constants.

The native rotation fixture checks both quarter-turns, nonzero bounds origins,
an off-center anchor, an already-transformed child, and preservation of point
mappings and the root frame. Unregistered/native controllers and throwing calls
are negative controls. `ownership`, `modern-explicit`, and `lifecycle` pass on
both iPad and iPhone with SDK 6.1 and SDK 11 (12 successful runs). The real
backing-layer assertions now check the upright published root and rotated child,
not the old root-transform representation. Full shared build, Classic geometry,
screen-metrics tests, compatibility 0/1 compile tests, and all six SDK fixture
builds pass.

The initial game retest reached Doodle Truck's world/level selection and tutorial,
Fragger gameplay (a visible throw reduced grenades from six to five), and Cling
Thing's first-level tutorial. All three were upright through two same-process
resumes in opposite landscape directions. Fragger's iPhone control also retained
its canvas through two resumes and accepted the visible Play button. Doodle's
iPhone cold/resumed canvas remained upright. These are smoke tests, not completed
playthroughs or real-iPadOS certification.

The final rebuilt simulator runtime (`05dd01c4d8f86368fee0360035b2a0f271e1e9eefee3125ef4b29a46ab43aa74`)
repeated cold launch and two opposite-landscape resumes for all three games.
Doodle Truck 2 (PID 13906), Fragger DS (14632), and Cling Thing (15207) each
retained their process and showed upright, centered, proportionate canvases at
both resume checkpoints. In particular, the first resume passed without an
intervening rotation: removing the experimental stale-screen equality check
resolved its small/offset Fragger and Cling output. Screenshots were taken
35 seconds after launch and 15 seconds after each resume; this verifies settled
output, not every frame of the transition. The matrix exited successfully, and
the Classic geometry, screen-metrics, and compatibility-switch tests passed
again against the final source.

**Initial repair limits (before the Flight Control follow-up below):** Fragger briefly displayed stretched/offset content after
resume despite correct model/presentation geometry; subsequent rendering restored
its centered aspect ratio without another runtime change. Flight Control HD is
not a full pass: text is upright and its logical canvas restores, but rotation
can retain the portrait panel arrangement, and a landscape Play-area press
opened Multiplayer instead. A later resume produced the proper landscape
notebook arrangement, but returning to portrait retained landscape panels.
Gameplay/input after arbitrary rotations is therefore still unresolved. No
game-specific touch correction was added. The Heist's intermittent redraw issue
from the baseline pass has not been retested or claimed fixed here.

Evidence remains in `/private/tmp/classic-ipad-resume-20261117/`, including
`doodle-native-label*`, `doodle-root-identity*`, `*-flat-*`, `flight-final-*`,
`native-regressions-{iphone-final,ipad}.log`, `*-retained-*.png`,
`retained-matrix.log`, and `regressions-retained.log`.

**Flight Control HD layout/input follow-up — 2026-11-17:** two general ordering
problems were reproduced in the shared runtime, using the same 1.07 copy,
original SDK fallback, and Classic Mode on the iPad simulator.

- `UpdateWindow` requested every turn with `force:YES`. UIKit's forced path
  skipped the normal legacy rotation lifecycle. The window rotated and resized,
  but the game retained its previous panel layout and touch-coordinate policy.
  A debugger-only `force:NO` experiment delivered the native callback and made
  the visible landscape Play button enter gameplay. Real turns now use the
  normal path; same-orientation initialization/layout refreshes remain forced.
- The turn that first exposed Classic loss could size the renderer from physical
  screen metrics before asynchronous normalization finished. The saved logical
  screen geometry and frame adapter were correct, but restoring only the window
  left its rotation client oversized. The setter trace recorded that assignment
  in `window:willAnimateRotationToInterfaceOrientation:duration:`. Normalization
  completion now restores the window and asks UIKit for a same-orientation native
  layout refresh using the saved metrics, without another guest rotation pair.

These changes reuse existing hooks and the normalization completion. No new
swizzles, touch remapping, game/device checks, canvas constants, or forced
physical orientation were introduced. The native regression now exercises the
production notification-to-UIKit path, requiring exactly one will/did pair per
accepted turn, correct old/new orientations, and no duplicate lifecycle on a
same-orientation refresh.

The final simulator framework SHA-256 is
`1bda1550753dcbda60567519015d650882aae38b01f85fec072e0081d22ee639`.
Flight Control PID 43182 retained upright, correctly proportioned portrait and
both landscape layouts. Visible Play, Pause, Continue, and Menu controls worked;
after resume and another landscape turn, dragging from a visible aircraft
created a visible route. Returning to portrait restored the portrait notebook
layout, and its Play button also entered gameplay. This is a layout/input smoke
test, not a completed round or a real-device certification.

Final verification also passed:

- Flight Control survived two same-process background/resume cycles, one in
  each landscape direction, without losing its map extent or orientation.
- All 24 native rotation fixture runs passed: nine each on iPhone and iPad
  (SDK 2/6.1/11, explicit/lifecycle/modern-explicit), plus six iPhone SDK 6.1
  rootless/manual/modal/ownership and modern-refresh controls. Classic geometry,
  screen-metrics, and compatibility-switch tests also passed.
- Doodle Truck 2 (PID 46317), Fragger DS (46925), and Cling Thing (47561) each
  retained the same process across both landscape resumes. Cold and resumed
  screenshots preserved orientation and proportions. These were visual resume
  checks, not additional gameplay/input tests. All test games were stopped.

The reported Cling Thing CPU usage was also reproduced on a fresh cold launch:
approximately 112% CPU, before any background/resume. The three-second sample
was dominated by display-link drawing and the simulator's software OpenGL
renderer (`GLRendererFloat`), not a repeating Classic/rotation-hook stack.
The sampled process was stopped; no frame-rate cap or game-specific performance
patch was added. Evidence: `cling-idle-cpu.sample.txt`.

Further evidence in the same local directory: `flight-layout-overwrite.log`,
`flight-classic-frame-query4.log` (saved geometry), `flight-classic-frame-values.log`,
`flight-reflow-*.png`, `flight-lifecycle-regression-iphone.log`,
`flight-lifecycle-regression-ipad.log`, `flight-negative-controls.log`,
`flight-reflow-regressions.log`, `flightreflow-matrix.log`, and
`{doodle,fragger,cling}-flightreflow-*.png`.

### Doodle Truck 2 and Cling Thing — portrait-launch Classic Mode, 2026-11-20

Doodle Truck 2 1.1.3 (original SDK 6.0) and Cling Thing 1.2 (SDK 7.0)
were launched by LiveContainer URL with Classic Mode enabled on the iPad
(A16) and iPhone 17 Pro Max simulators, both on iOS 27. Each cold launch was
compared with a Home/foreground cycle in the same process. The checks are of
the visible menus and their proportions, not gameplay or touch coverage.

**iPad:** With the simulator held portrait, the multitasking host imposed an
all-orientations policy. Doodle Truck stretched its title vertically; Cling
Thing lost the right side of its menu. UIKit rejected a landscape geometry
request with scene error 101. The shared runtime now lets a verified legacy
Classic scene publish its actual window policy. When the foreground scene's
orientation falls outside that mask, the runtime requests a supported
orientation, including after an ordinary resume. It does not force either
landscape side, change the sensor, or resize the renderer. Both games show
the complete 4:3 canvas, the same 2186 × 1640 content pixels as a landscape
launch. With the iPad held portrait, the system capture remains portrait and
the game is turned within it; that is not a portrait-sized game view.

**iPhone (zoom still open):** Both games already turn landscape. A portrait
launch uses a 960-pixel-high canvas; a landscape launch uses 1242 pixels.
Home/foreground preserves the respective size. The game receives the same
logical screen; the difference is in SpringBoard's Classic presentation.
A native control with a landscape-only controller and no LC32 reproduced it:

| Installed host orientations | In-process orientations before UIKit startup | Classic frame width on portrait launch (points) |
| --- | --- | ---: |
| Portrait and landscape | Portrait and landscape, or landscape only | 320 |
| Landscape only | Landscape only, or portrait and landscape | 414 |

All four controls received the 414-point width on landscape launches. The
inverted cases changed only the disposable control's in-memory bundle cache;
both NSBundle and CFBundle reads were checked before UIApplicationMain. A
client zoom change or self-reactivation also failed to enlarge the live
Classic frame. Changing the guest's scale would not change that outer
boundary. No iPhone scale override or installed LiveContainer plist change was
made.

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
