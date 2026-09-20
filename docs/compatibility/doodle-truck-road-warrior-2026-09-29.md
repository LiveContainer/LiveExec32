# Doodle Truck canvas and Road Warrior vm_remap

2026-09-29, based on `08866c4`, with real-device follow-ups through 2026-10-03 below.
Device menu/rendering verification is not full gameplay certification. The
dated sections retain the evidence and limitations of each test pass.

## Doodle Truck 1 / 2

Tested installed Doodle Truck **1.7.8** (original SDK 7) and Doodle Truck 2
**1.1.3** (original SDK 6), with Classic Mode enabled on the iPhone 17 Pro Max /
iOS 27 simulator. Initial reproduction also used LC's legacy SDK-2 override.

The simulator's renderer view reaches **568×320** landscape bounds. Native UIKit subsequently
sets its bounds to **568×300**, reserving a **20-point status-bar inset** despite
`UIApplication.isStatusBarHidden == YES`. In portrait window coordinates the
renderer occupies `(0,0,300,568)` or `(20,0,300,568)`, depending on rotation.
The engine retains its original projection and uses raw view-relative touch
coordinates. Compressing only the view therefore misaligns drawing and input.

LLDB traced the resize through `UIViewController window:setupWithInterfaceOrientation:`
to `_boundsForOrientation:` and `_centerForOrientation:`. Both use
`UIScreen _applicationFrameForInterfaceOrientation:usingStatusbarHeight:ignoreStatusBar:`
with the default status-bar height and `ignoreStatusBar:NO`. The public
`UIScreen.applicationFrame` already returns the full screen; overriding that
public getter or the controller's `prefersStatusBarHidden` does not fix this path.

One swizzle in `LegacyRotation.mm` makes that private frame query ignore a
currently hidden status bar. It retains native geometry, explicit ignore
requests, visible-bar behavior, and all other arguments. It is installed only
under the existing **pre-SDK-8** and `LC32_UIKIT_COMPATIBILITY` gates. There are
no game-name checks, fixed dimensions, or touch-coordinate hooks. Class lookup
in `+load` avoids triggering `UIScreen +initialize` while the runtime is being
loaded by LiveContainer.

Retests reach both menus with a full `(0,0,320,568)` portrait-window frame and
**568×320** renderer bounds. Doodle Truck 2 retains the full extent in both
landscape directions. Doodle Truck 1 retains the full extent through both
physical landscape requests (its renderer retains its chosen direction).
SDK 11's actual Doodle Truck 2 process reports the legacy gate disabled and
retains the native UIKit implementation of the frame selector.

This fixes the reproduced inset, not every possible stretch: repeated simulator
Classic Mode transitions can change the screen extent independently. Touch
gameplay and the reported real-device result still require retesting. The
pre-Sheep-drawable-fix runtime also reproduces the inset, so this pass does not
attribute it to that recent fix or identify the introducing commit.

### 2026-09-30: remaining stretch on the real phone

Attached on-device LLDB to the already-running standalone Doodle Truck **1.7.8**
on an iPhone 15 Pro Max / iOS **26.1 (23B50)**, original SDK **7**. The previous
hidden-status-bar hook is present and working; this is not a stale installation.
The measurements above describe **view geometry**, not proof that the game's
OpenGL drawable and projection match it.

The remaining mismatch is:

| Measurement | On-device result |
| --- | --- |
| Window / renderer frame, portrait coordinates | 320×568 |
| Rotated renderer bounds | 568×320 |
| Game's stored EAGLView surface size | 480×320 |
| OpenGL renderbuffer / viewport | 480×320 |
| Projection X / Y scale | 2/480, 2/320 |
| `autoresizesSurface` | NO |

The fixed 480-wide image is therefore expanded to 568 points, about **18.3%**
horizontal stretch. The drawing and view-relative touch coordinate spaces no
longer agree. Removing the 20-point inset did not address this second mismatch.

Disassembly identifies `ShellIsRuniPhone5()` as the canvas-size decision. It
checks that `UIScreen` implements `currentMode`, then compares its size with
**640×1136** exactly. False selects 480×320; true selects 568×320. Reinvoking
this read-only predicate through `LC32InvokeGuestC` in the settled process still
returns **0**, ruling out a startup-only mode change.

LLDB traced its actual bridge calls through `mainScreen`, `currentMode`, and
`-[UIScreenMode size]`. UIKit itself returns **960×1704** in `d0/d1`, before
marshalling; the guest's `UIScreen.scale` likewise returns **3**. A direct
debugger call and the mode's description instead report **640×1136** / **2**.
This is not float/double conversion corruption, and `po currentMode` alone
conceals the discrepancy.

`-[UIScreenMode size]` calls `_sizeWithLevel:2`, which calls
`_UIScreenForcedMainScreenScale`. That function walks the native frame chain
and uses the caller's image path to choose the compatibility scale. The actual
guest call is attributed to the external runtime:

```
/dopamine-8sAUqp/procursus/Applications/LiveExec32.app/Frameworks/LiveExec32Shared.framework/LiveExec32Shared
```

It retains the native **3×** scale, rather than the cached legacy **2×** scale.
An additional device-specific complication is that `_dyld_get_image_name(0)`
and UIKit's cached executable path point to `basebin/systemhook.dylib`, with
the cached directory prefix `basebin/`, not the game's bundle. The runtime is
outside that prefix. This explains why simulator-only geometry retests missed
the actual on-device screen-mode result; it does not establish which historical
commit introduced the stretch.

A read-only call to `-[UIScreenMode _sizeWithLevel:0]` returns the correct
**640×1136** using UIKit's compatibility policy without caller classification.
The proposed fix is to give guest screen-scale/mode queries the **application's
legacy scale**, consistently and only where that policy applies. Do not fix it
by stretching the projection, changing touch coordinates, or unconditionally
forcing 480 points / 2× on iPads, external displays, or modern-SDK apps.
No new runtime fix was installed in this diagnostic pass.

Doodle Truck 2 **1.1.3** has the same 640×1136 predicate in its disassembly,
making the same cause likely, but its running device process was not retested
in this pass. A fix still needs both games and native iPad / modern-SDK controls.

Evidence: `tmp/doodle-device-20260930/truck1-device-before.png`,
`truck1-info.txt`, `truck1-objc.txt`, `truck1-disassembly.txt`, and the on-device
LLDB observations above. The game was not relaunched or patched. All diagnostic
breakpoints were deleted and LLDB detached; no Mac keyboard/mouse input was used.

### Screen-metrics implementation and retest

`HostFrameworks/UIKit/GuestScreenMetrics.mm` registers two **guest-only**
selector adapters, for `UIScreen.scale` and `UIScreenMode.size`. Native UIKit
messages are not swizzled. Registration uses the existing native pre-SDK-8
policy, honors `LC32_UIKIT_COMPATIBILITY` and the runtime disable switch, and
requires `_sizeWithLevel:`. Missing private API leaves both getters native.

The mode adapter asks UIKit for `_sizeWithLevel:0`. The scale adapter compares
that application-mode size with the unadapted mode size and applies the same
ratio to the unadapted screen scale. Both unadapted calls originate in the same
runtime image, so caller classification is consistent. This avoids hard-coded
2× / 640×1136 values, deriving pixels from window bounds, native display changes,
game identifiers, or touch-coordinate hooks. Missing/invalid mode widths retain
the original scale. Existing guest iPad-canvas policy remains separate.

The candidate shared framework was built and deployed to the phone's external
LiveExec32 installation, preserving the previous framework under
`/var/tmp/lc32-screen-metrics.97tWj0/`. Neither game bundle, SDK setting, nor save
directory was edited.

- **Doodle Truck 1.7.8 / SDK 7:** `ShellIsRuniPhone5()` now returns **1**;
  actual guest `UIScreen.scale` is **2**. Stored surface, GL renderbuffer, and
  viewport are all **568×320**. Projection factors are **2/568, 2/320** and the
  view fills the 320×568 portrait window. The previous horizontal mismatch is
  removed.
- **Doodle Truck 2 1.1.3 / SDK 6:** the same predicate now returns **1** and
  actual guest scale is **2**. Its Retina renderer correctly allocates
  **1136×640** pixels, with a matching viewport and **2/568, 2/320** logical
  projection. The final cold-launch retest has **568×320-point view bounds**,
  `contentScaleFactor=2`, and a full `(0,0,320,568)` portrait-window frame.

Truck 2 required a second correction: after the screen-mode fix, its view still
measured **568×300** because UIKit selected controller-managed status bars even
for this SDK 6 application. `UIStatusBarHidden=YES` was consequently ignored.
Its `UIViewControllerBasedStatusBarAppearance` key is absent, unlike Truck 1's
explicit `NO`. A reversible LLDB method replacement confirmed that application-
managed policy allows the normal `setStatusBarHidden:` API to work; that
experimental replacement was restored before testing the compiled fix.

`LegacyRotation.mm` now defaults `_viewControllerBasedStatusBarAppearance` to
`NO` only for **pre-SDK-7**, compatibility-enabled processes **without an
explicit plist choice**. This restores the old application-level policy rather
than forcing the bar hidden: explicit `YES`/`NO`, SDK 7+, and native show/hide
requests retain their behavior. The existing hidden-bar frame correction then
removes the inset. The final device process reports application-managed policy,
`isStatusBarHidden=YES`, and matched view/render/projection dimensions.

Validation for the screen-metrics adapter:

- **120** deterministic host checks pass across compatibility on/off, legacy /
  modern policy, and private API present/absent. Covers the actual 3×→2× ratio,
  native-call isolation, iPad-like and external-display modes, nil modes, and
  zero/nonfinite mode widths.
- **160** native iPhone/iPad simulator checks pass (16 launches: SDK 7/11,
  build switch on/off, runtime disable on/off). The installed **iOS 27 simulator
  lacks `_sizeWithLevel:`**, so these verify native fallback and unchanged
  screen values, not the iOS 26.1 device correction. The fixture explicitly
  reports that limitation and verifies its effective SDK.
- Existing selector registry: **10** checks pass. UIKit compatibility-switch
  compile tests pass for both modes, including the new unit. Shared-framework
  and aggregate app builds pass; `git diff --check` passes.
- Status-bar regressions: **12** native iPhone/iPad launches pass. Covers SDK
  6.1/7/11 defaults, explicit application/controller policy, initial hidden-bar
  state, legacy show/hide calls, original method preservation, and frame-query
  arguments/results. Final device evidence is `truck2-device-final.log`.

### Final normal-launch device verification

Both games reach visibly working, correctly proportioned menus with the final
candidate after a **normal phone-side launch** (`uiopen --bundleid`, over SSH).
Truck 1's graph-paper cells are square again rather than horizontally widened;
Truck 2's paper grid and circular truck wheels likewise retain their proportions.
The games can keep their own centered 480-point menu artwork within the wider
568-point canvas; the fix does not stretch that artwork to fill the canvas.

An apparent black-screen regression was isolated to the **developer launch
path**, not this patch. `pymobiledevice3 developer dvt launch` produced a black
foreground for the final candidate, a control with the new adapters disabled,
and the exact original phone runtime. An early original-runtime capture showed
only a transient launch snapshot; a settled capture was also black. In the
candidate, the GL framebuffer was complete, readback contained menu pixels,
and `presentRenderbuffer:` returned `YES`. Cold-launching through `uiopen`
displayed both original and candidate correctly. No compositor workaround was
added. A debugger expression evaluated while stopped in JIT code caused one
diagnostic-only abort; that run was excluded and restarted. Final measurements
use a native `presentRenderbuffer:` breakpoint.

Final screenshots: `truck1-original-uiopen-settled.png` (stretched control),
`truck1-fixed-uiopen.png`, and `truck2-fixed-uiopen.png`. The normal-launch Truck 1
process also confirms **568×320** stored surface/renderbuffer/viewport/view,
**2/568, 2/320** projection, helper result **1**, and guest scale **2** in
`truck1-normal-final.log`.
Truck 2's normal-launch process confirms **1136×640** stored surface/renderbuffer/
viewport, **568×320** view bounds, the same logical projection, helper result
**1**, and guest scale **2** in `truck2-normal-final.log`.

Touch gameplay and physical rotation are not certified by these menu and
dimensional checks. The final candidate remains installed; the original runtime
is retained in the device staging directory above. Game bundles and SDK settings
are unchanged, and no Mac keyboard/mouse input was used. All task-created
debuggers were detached and closed. The device-tested shared-framework UUID is
`A7001700-A42E-38F5-9219-B2FED1B062A9`. Evidence is under
`tmp/doodle-device-20260930/`; the `*-screen-metrics-final.log` files are the final
simulator controls, superseding initial fixture attempts.

## Road Warrior 1.4.8

The phone's crash report identifies Mach message **3814** as `vm_remap`. Its
caller allocates a double-length audio circular buffer, unmaps the second half,
and remaps the first half there with `copy=FALSE`. A copied buffer or a success
stub would not implement this operation.

Added the ARM32 MIG request/reply handler and shared guest-page aliases. The
implementation retains backing references across aliases, handles fixed,
anywhere, and overlapping-overwrite mappings, validates the request and source
range before mutation, and preserves per-page permissions. Invalid requests
return errors rather than terminating the emulator. The wire layout was checked
against the iOS 10.3 Mach headers and Apple's
[vm_map definitions](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_map.defs).

Scope is aligned, same-task, non-COW owned data mappings. COW, unaligned
extraction, external backing, and executable aliases remain explicitly
unsupported. Maximum permissions are not separately tracked by the guest VM;
the reply conservatively reports the intersection of source permissions.

The previously installed simulator copy is **1.4.2**, which is not a matching
reproduction. Copied the existing **1.4.8** app bundle from the phone over Wi-Fi
SSH into an isolated simulator test bundle. No phone files or app data changed.
LiveContainer auto-created `LCAppInfo.plist`, but initially classified this
device-patched FAT binary as 64-bit because it includes an injected ARM64
launcher. Extracting its original ARMv7 slice and correcting only the test
metadata allowed the normal 32-bit runtime launch. No archive download was needed.

**The reported Mach-message failure is fixed; the game is not yet verified
playable.** Version 1.4.8 progresses past it, then faults at guest address zero
in framebuffer setup (`3r` PC `0x110a625e`, adjacent to `glCheckFramebufferStatus`).
This is a separate remaining simulator rendering-path crash, not a successful
gameplay result. It has not been established whether this later failure occurs
on the phone. Earlier 1.4.2 framebuffer trouble is documented in
[the previous Road Warrior report](road-warrior-debug-2026-09-22.md).

### SystemConfiguration follow-up — 2026-10-02

Implemented the subsequently reported missing
`SCNetworkReachabilitySetDispatchQueue` export. The existing guest reachability
object now supports asynchronous notification on the supplied queue, retains
the scheduled target and queue, and suppresses work from cancelled schedules.
Queue and run-loop scheduling cannot be mixed. Callback/context snapshots are
protected by the target lock, but client callbacks execute outside it, allowing
self-cancellation. Scheduling and cancellation follow the contract in Apple's
[implementation](https://github.com/apple-oss-distributions/configd/blob/main/SystemConfiguration.fproj/SCNetworkReachability.c).

Also added native-backed, read-only queries:

- `SCDynamicStoreCopyComputerName` (including its 32-bit encoding output).
- `SCDynamicStoreCopyLocalHostName`, `SCDynamicStoreCopyLocation`, and
  `SCDynamicStoreCopyProxies`.
- `CNCopySupportedInterfaces` and `CNCopyCurrentNetworkInfo`, replacing their
  previous empty-array/NULL stubs.

The host bridge transfers each native Copy result's ownership to its guest
proxy and preserves native failures. Historical exports are resolved optionally;
missing functions return NULL with an error. `SCError` is now thread-local, and
`SCCopyLastError` reflects it. No configuration writes, permission changes, or
dynamic-store session/subscription APIs were added.

**Scope limitation:** reachability still reports the existing fixed
`kSCNetworkReachabilityFlagsReachable` compatibility value. This is queue
scheduling support, not a native reachability monitor. Wi-Fi getters remain
subject to native privacy and entitlement restrictions.

Validation:

- Host: **43** reachability checks and **28** copy-bridge checks pass, covering
  queue identity, deferred delivery, cancellation/rescheduling, target/context
  lifetimes, self-cancellation, late callback registration, run-loop exclusion,
  thread-local errors, shared ABI layout, owned results, and native failures.
- Real iPhone: **63** ARM32 checks pass through the installed LiveExec32 runtime.
- iPhone 17 Pro Max and iPad A16 simulators: **62** ARM32 checks each pass.
  The count differs because successful native queries receive an additional
  status check; unavailable/private information is allowed to return NULL.
- The public-symbol audit passes **819** exports, including all seven exports
  added or upgraded here. Guest framework and aggregate host builds pass.

The phone has the updated host and guest framework pair installed. Previous
copies are retained in `/var/tmp/lc32-systemconfiguration.CFTqaE/`. The repository
RootFS also contains the rebuilt guest shim. **Road Warrior gameplay is still
unverified:** the normal remote launch did not start the game, and the captured
screen was black. Asked the user to unlock the phone and open Road Warrior; this
is not recorded as either a successful game launch or a new reproduced crash.
No debugger was attached during this follow-up.

Evidence: `tmp/systemconfiguration-host-test.log`,
`tmp/systemconfiguration-device-test.log`,
`tmp/systemconfiguration-iphone-sim.log`,
`tmp/systemconfiguration-ipad-sim.log`, and
`tmp/systemconfiguration-symbol-audit.log`.

### Road Warrior simulator retest — 2026-10-02

Tested the phone-matching **1.4.8** copy on the iPhone 17 Pro Max / iOS 27
simulator with the updated SystemConfiguration shim and host runtime. Used an
isolated app/data clone and per-game runtime selection, retaining **Legacy SDK
(LC override 2.0) and Classic Mode**. The installed 1.4.2 copy was not changed.

**Still not playable in the simulator.** The debugger captured the same
graphics-path failure as the September 29 test:

```text
Signal: SIGSEGV
MemoryRead64 at guest address 0x00000000
guest PC: 0x110a625e (3r + 0xa225e)
adjacent guest frame: glCheckFramebufferStatus + 0x72
```

There was no missing-SystemConfiguration-symbol error in this run, but this
startup failure prevents a complete game/networking retest. The result does
not establish whether the graphics failure also occurs on a real device.
No touch/gameplay tests or additional runtime fixes were made in this pass.

The initial URL launch did not yield a confirmed game process. For the captured
diagnostic run, launched LC with its `selected` / `selectedContainer` argument
overrides and attached LLDB before startup. The crash report confirms the
isolated game's and runtime's paths. This was a crash diagnosis, not a viewport
or orientation validation. LLDB detached and quit afterward; temporary LC links
were removed and the isolated test save was retained with the evidence.

Evidence: `tmp/road-sc-sim.LPy9l0/native-watch.log`, `session.sh`, the test bundles,
and `test-save-after/`. The native log includes the complete guest crash report;
its much longer all-thread native backtrace was truncated in capture.

### Road Warrior framebuffer root cause — 2026-10-02

Traced the 1.4.8 null dereference through both the ARM32 framebuffer initializer
and the native CoreVideo calls. **The immediate blocker is the iOS 27 simulator's
native IOSurface/OpenGL ES interop, not a missing SystemConfiguration bridge.**
The game is still not verified playable; this finding is not a runtime fix.

The sequence is:

1. `CVPixelBufferCreate` succeeds for a **660×1434 BGRA** buffer with
   `kCVPixelBufferIOSurfacePropertiesKey: {}`.
2. `CVOpenGLESTextureCacheCreate` succeeds with the game's native EAGL context.
3. `CVOpenGLESTextureCacheCreateTextureFromImage` returns **-6683**
   (`kCVReturnPixelBufferNotOpenGLCompatible`) and a NULL texture.
4. The game's helper at guest `0x110a35b0` frees its framebuffer wrapper and
   returns NULL. Its caller stores this at state offset `0x30`, then
   dereferences it in the block starting at `0x110a625e`. The adjacent
   `glCheckFramebufferStatus` checks a different, successfully created FBO.

A standalone native ARM64 simulator probe, with **no LiveExec32 bridge loaded**,
reproduces -6683 with both 64×64 and 660×1434 buffers, literal/native attribute
keys, and explicit OpenGLES compatibility. Every IOSurface-backed buffer has a
non-NULL IOSurface. The game already meets the backing requirement described in
[Apple QA1781](https://developer.apple.com/library/archive/qa/qa1781/_index.html);
adding that key again is not a fix.

Native LLDB disassembly identifies the hard limitation in this runtime:

```text
CVOpenGLESContext::texImageIOSurface(...):
    mov w0, #0
    ret
```

This method unconditionally reports failure. The private EAGL
`texImageIOSurface:target:internalFormat:width:height:format:type:plane:` path
also returns NO in the native control.

Removing IOSurface backing lets native CoreVideo create ordinary CPU-uploaded
textures, but it is **not an equivalent fallback**: after `glClear` and
`glFinish`, locking the pixel buffer still returns its original pixels, not the
GPU-written pixels. Dropping the attribute would conceal the startup crash while
breaking GPU-to-buffer synchronization needed for recording. No such workaround,
game-specific bypass, or fabricated success was added. A general simulator fix
would need synchronized texture/pixel-buffer emulation beyond the existing
native bridge.

The SSH-only iPhone control was inconclusive: it could not create an EAGL context
and failed before the texture-cache path. It must not be counted as either a
device pass or reproduction of the simulator failure. A foreground device
retest was requested.

Evidence: `tmp/road-framebuffer.VyK0Ul/native-lldb2.log`,
`native-surface-import-disasm.log`, `cv-native-probe.log`,
`cv-native-extended.log`, `cv-native-sync.log`, `cv-device-sync.log`, and
`cv-probe.m`. The probe is diagnostic only, not a passing regression fixture.
All task debuggers exited. Removed the two temporary simulator links and the
uploaded phone probe; retained the isolated simulator save, probe binaries,
source, and logs locally. No game installs, original saves, or production
runtime code were changed in this diagnostic pass.

### Road Warrior Wi-Fi device fixes — 2026-10-02

Retested the installed standalone **1.4.8** on the iPhone 15 Pro Max / iOS 26.1
over Wi-Fi SSH and on-device LLDB, with its existing SDK and Classic Mode
settings unchanged. Normal foreground launch uses `uiopen` as mobile, not a
developer-process launch. No Mac keyboard/mouse input was used.

The real game's native `CVOpenGLESTextureCacheCreateTextureFromImage` returns
**0 and a non-NULL texture** for its **1136×640 BGRA** buffer. This supersedes the
inconclusive SSH-only graphics probe above: the simulator framebuffer blocker
does not reproduce on this device.

Three further blockers were found and addressed:

1. **Missing CoreMedia sample creation.** The first foreground crash reports
   `_CMAudioFormatDescriptionCreate`. Added this API, `CMSampleBufferCreate`,
   `CMSampleBufferSetDataBufferFromAudioBufferList`, and
   `CMSampleBufferSetDataReady`, forwarding to native CoreMedia. The bridge
   copies guest ASBD/channel-layout/cookie/timing data, widens 32-bit sample-size
   arrays, reconstructs the 32-bit AudioBufferList, and transfers Create-result
   ownership. Native CoreMedia owns a copy of the PCM bytes. Guest allocator
   identities are mapped explicitly; custom allocators and make-data-ready
   callbacks remain unsupported rather than passing guest code pointers to
   native code. Existing small CoreMedia requests remain readable at page
   boundaries after extending the request structure.
2. **Guest suspension deadlock during startup.** The main thread waits in
   `ChangeGuestThreadSuspendCount` while another guest thread stays inside
   native `CFRunLoopRun`. That bridge did not publish stable guest registers,
   so suspension could never be acknowledged until the loop returned. A scoped
   guard now uses the existing host-call quiescence mechanism around
   `CFRunLoopRun` and `CFRunLoopRunInMode`. Guest callback entry still respects
   suspension. The new bounded ARM32 test times out before this fix and passes
   both variants afterward. LLDB then observes the game executing display-link
   callbacks and entering `presentRenderbuffer:`; the user confirms the title
   menu appears. This is not yet a gameplay pass.
3. **Match-start recording selectors omitted by generated shims.** The user's
   first match attempt aborts with
   `-[AVAssetWriter startSessionAtSourceTime:]: unrecognized selector`.
   Generated methods with anonymous `CMTime` / opaque sample-buffer types were
   disabled. Initially added typed guest adapters for `startSessionAtSourceTime:`,
   `endSessionAtSourceTime:`, `appendPixelBuffer:withPresentationTime:`, and
   `appendSampleBuffer:`. They use the existing aggregate/object transport and
   native AVFoundation implementation. No recording bypass, game-name check,
   or fabricated successful return was added. The Garage follow-up below
   replaces these four manual adapters with shared generator support.

Validation:

- CoreMedia: **28 host checks** and **22 ARM32 device checks** pass, including
  ownership, timing, planar/interleaved PCM, copied-buffer lifetime, output
  canaries, malformed requests, unsupported callbacks, and error propagation.
- Run-loop suspension: **16 ARM32 checks** pass, covering suspension in both
  native run-loop entry points, deferred callbacks, resume, and loop exit.
- Existing thread suspension and blocking-host-call tests: **56 + 16 device
  checks** pass. Existing CoreMedia time-value host checks also pass.
- Existing run-loop, source, and timer fixtures: **31 device checks** pass on
  the final retry (see the initial failed attempt below).
- Recording: **21 ARM32 device checks** pass. The test writes two H.264 frames
  and 2940 PCM audio samples, starting at a nonzero source time (7/3 seconds),
  then ends the session and finishes the movie. Independent `ffprobe` inspection
  confirms video timestamps **0 and 1/30 seconds**, audio/video start at zero,
  and both stream durations **2/30 seconds**. This checks actual output, not
  only selector availability.
- Guest/host builds and `git diff --check` pass.

The initial older run-loop CLI fixture attempt was terminated by an iOS
`EXC_GUARD / REQUIRE_REPLY_PORT_SEMANTICS` in the guest Mach-message forwarding
path; its following source/timer fixtures did not run in that attempt. All three
then pass unchanged on the installed candidate, so this is recorded as an
intermittent unresolved diagnostic, not a fixed failure. An attempted old-host
comparison still loaded the candidate (verified by UUID); it is not baseline
evidence. This is distinct from Road Warrior's captured AVAssetWriter exception.

The CoreMedia, CoreFoundation, and AVFoundation candidates remain installed.
Original host, CoreMedia, and AVFoundation frameworks are retained under
`/var/tmp/lc32-road-coremedia.MwA5QA/`; game bundles and saves were not patched.
The host UUID for this initial pass is `9DECDE8F-D640-3B91-8A12-89AC55E42721`. Task-created LLDB
sessions detached and exited. Wi-Fi screenshots timed out after the initial
MOBJOY splash capture; title-menu confirmation came from the user, not a later
screenshot. Road Warrior was relaunched after the recording fix for a new match
attempt; the user subsequently confirmed completing a match, then reported
the separate Garage crash below.

Evidence: `tmp/road-wifi.IgogOj/`, including `first-launch.ips`,
`post-fix-thread-stacks.log`, `runloop-before.log`, `runloop-after.log`,
`final-device-regressions.log`, `final-host-regressions.log`, `match-start.ips`,
`av-writer-device.log`, `recording-result.mov`, `recording-result.json`, and
`cf-runloop-test.ips` / `cf-device-retry.log`.

### Road Warrior Garage / video-composition follow-up — 2026-10-02

After completing a match, pressing Garage aborts with
`-[AVMutableVideoComposition setFrameDuration:]: unrecognized selector`.
The captured device report is `3r-2026-10-02-214140.ips` (local `garage.ips`).
The exception occurs in the replay/export path, not the earlier framebuffer
or CoreMedia sample-creation paths.

The generator now recognizes the exact anonymous and named encodings of
`CMTime` and `CMTimeRange`, plus the known opaque CF sample-buffer and
format-description types. Time values have fixed-width fields and use the
existing aggregate transport; the CF types use existing object proxies and
ownership handling. This replaces the temporary four-method writer adapter
and enables time-valued composition, asset, track, and Foundation `NSValue`
methods without class- or game-specific dispatch checks. Other anonymous
structs and arbitrary opaque pointers remain disabled.

The end-to-end test also exposed an existing host return-value gap: a native
24-byte `CMTime` result was rejected by the size-based struct-return switch.
The host now uses the existing numeric-struct parser to identify non-HFA
aggregates larger than 16 bytes, supplies native result storage through ARM64
`x8`, and copies the signature's exact size back to the guest. Existing
floating-point aggregate and `NSRange` return paths remain in place.

Validation:

- Generator CoreMedia fixture passes, including named/anonymous layouts,
  mixed arguments, borrowed/owned CF results, and negative controls. Existing
  scalar/object generator fixtures also pass, including ARMv7 syntax checks.
- Generated AVFoundation, Foundation, and Photos frameworks build. The
  AVFoundation/Foundation candidates and updated host are installed on the
  phone; Photos was built locally, not deployed for this game.
- **30 ARM32 device checks pass**: the previous writer checks, wide-field
  `NSValue` time/range round-trips, asset duration, track range, composition
  frame duration, instruction range, and actual composed movie export.
- Existing ARM32 guest/host aggregate checks (**7**) and structure-forwarding
  checks (**17**) also pass on the phone. These cover geometry, large affine
  transform returns, native-to-guest callbacks, mixed/padded values, register
  exhaustion, and output canaries; both guests exit zero.
- Independent `ffprobe` inspection of the composed movie confirms **two
  32×32 H.264 video frames**, an AAC audio stream, zero start times, and
  **2/30-second durations** for both streams.
- The first expanded test run had four failures due to the 24-byte return
  gap; the same fixture passes all 30 checks after the host fix. An earlier
  failed test link ran a stale binary and is not validation evidence.

Latest installed host UUID: `26AE70AB-C41C-3C6A-9D94-B4A547960C34`.
Original host, Foundation, CoreMedia, and AVFoundation backups remain in the
device test directory. At this stage, the automated export test passed but the
game's exact finish-match → Garage sequence was not yet verified. The subsequent
thumbnail fix and successful gameplay retest are recorded below.

Evidence in `tmp/road-wifi.IgogOj/`: `garage.ips`,
`time-generator-test.log`, `generator-scalar-test.log`,
`generator-objects-test.log`, `av-time-build-final.log`,
`av-composition-device-final.log`, `indirect-return-host-build.log`,
`av-composition-return-fixed.log`, `aggregate-recheck-device.log`, and
`composition-result.mov`.

### Road Warrior replay-thumbnail follow-up — 2026-10-03

The user reported another Garage crash and quoted `setFrameDuration:` again.
However, the latest device report (`3r-2026-10-02-221245.ips`, PID 65369) loads
the new host UUID above and instead aborts in `LC32GuestForwardInvocation`.
The installed AVFoundation checksum matches the composition-tested candidate.
Disassembling the phone's ARMv7 executable places the game in
`extractThumbnailFromAsset:`, which calls
`-[AVAssetImageGenerator copyCGImageAtTime:actualTime:error:]`.

Extending the recording fixture reproduces that second failure on the phone:
all 30 recording/composition assertions pass, followed by
`cannot forward guest -[AVAssetImageGenerator copyCGImageAtTime:actualTime:error:]: unsupported return encoding`.
The missing method had remained disabled because its `actualTime` argument is
a `CMTime *`, not a by-value time. The shared forwarding assembly's nearby
`LC32GuestForwardMessageStret` symbol in the stack was not evidence that this
CGImage-returning method actually uses a struct-return ABI.

Added one typed AVAssetImageGenerator adapter. It uses the existing bounded
indirect transport for exactly one 24-byte `CMTime` output, the existing
NSError output cell, and owned CGImage object-proxy conversion. It preserves
NULL outputs and native errors; arbitrary struct pointers and arrays remain
disabled. The generator explicitly leaves this selector to its manual adapter.

Validation and installed state:

- Generator fixture and AVFoundation build pass. Generated output contains
  no duplicate thumbnail implementation; the linked shim contains the method.
- **36 ARM32 checks pass in the iPhone simulator**, including the original
  writer/composition assertions, actual thumbnail extraction, 32×32 image
  dimensions, returned time, output canaries, NULL outputs, and native error
  propagation. Guest exits zero. This uses an isolated runtime copy, without
  reinstalling or editing game bundles/settings/saves.
- Phone CLI launches repeatedly hit the previously observed native
  `EXC_GUARD / REQUIRE_REPLY_PORT_SEMANTICS` before `main`. LLDB captures it in
  legacy XPC-message forwarding. One unchanged pre-fix run reached and
  reproduced the thumbnail failure above, but post-fix phone fixtures have
  not completed. No platform restriction, entitlement, or assertion was
  disabled to obtain a pass; the startup guard remains unresolved.
- The thumbnail candidate is installed over USB using pymobiledevice3 from
  the user's venv. AVFoundation SHA-256 is
  `1c99835ad9707a825600beb8b56350a30ed94ebff57eb93abddb3371e14f684a`.
  The host is unchanged. The immediately preceding AVFoundation is backed up
  at `/var/tmp/lc32-road-coremedia.MwA5QA/AVFoundation-before-thumbnail`.
- After a normal Road Warrior launch, the user confirmed on **2026-10-03**
  that the finish-match → Garage sequence works with the thumbnail candidate
  installed on the phone. This is user-confirmed gameplay, separate from the
  automated simulator checks above. Task LLDB sessions and the USB forwarding
  tunnel have exited; the game was left running. No Mac keyboard/mouse input
  was used.

Evidence in `tmp/road-wifi.IgogOj/`: `garage-retest.ips`,
`device-3r-armv7`, `thumbnail-guard-message.log` (the pre-fix thumbnail
reproduction), `thumbnail-initial-cli.ips`, `thumbnail-usb-before.ips`,
`thumbnail-guard-symbols.log`, `thumbnail-shim-build.log`,
`thumbnail-fixed-lldb.log`, and `thumbnail-simulator.log`.
The isolated simulator runtime/output is under `tmp/road-thumbnail-sim.2bHqfG/`.

### Remaining generated method-type audit

After the time-type fix, **1,640 generated method entries** remain disabled
for unhandled types. This is not a count of missing runtime methods: the
snapshot includes private APIs, duplicated framework classes, and methods
already implemented by manual adapters. Counts below mean generated entries
where the listed type is the only reported type blocker, not tested APIs.
The later manual thumbnail adapter removes one additional disabled entry;
the table retains the original audit counts.

| Candidate | Entries | Implementation considerations |
| --- | ---: | --- |
| `CGVector` | 38 | Two `CGFloat` fields; reuse the explicit 32→64-bit conversion pattern used by `CGPoint`. |
| `UIOffset` | 26 | Same two-`CGFloat` layout pattern. |
| `CLLocationCoordinate2D` | 54 | Two fixed-width doubles; compatible with the existing two-double argument/return path. |
| `AudioComponentDescription` | 18 | Five fixed-width UInt32 fields; explicit value adapter with indirect-aggregate regression tests. |
| `CGColorSpaceRef` | 42 | Explicit known-CF-type recognition, with object-proxy and ownership tests. |
| `CGPathRef` | 23 | Same, plus eight additional const-qualified entries. |
| `CGContextRef` | 20 | Same; verify native context identity and borrowed-result lifetime. |
| `oneway void` | 6 | Normalize the non-layout `V` qualifier when classifying the method return. |

Next-tier candidates are `CMTime *`, `CMTimeRange *`, and `NSRange *`:
they need bounded input/output staging, direction/nullability handling, and
copy-back; they cannot simply be passed as guest pointers. `NSRange` also
requires width and `NSNotFound` conversion.

`SCNVector3`/`SCNVector4` and GLKit vector unions are not generator-only wins:
the host argument classifier still assumes double HFAs for the common
16/32-byte cases, so float vectors need register-classification work and tests.
`CATransform3D` grows from 64 to 128 bytes and exceeds current 64-byte aggregate
argument storage. Arbitrary `void *`, callback pointers, and private opaque
handles require explicit memory/lifetime contracts rather than blanket object
conversion. These candidates were audited, not enabled in this pass.

## Validation

- `vm-remap`: **28** native macOS checks and **46** ARM32-emulated checks pass.
  Covers bidirectional sharing, wraparound, source removal, overwrite/overlap,
  alignment, independent alias protection, source holes, malformed ARM32
  requests, short replies, and explicitly unsupported COW/unaligned requests.
- Existing VM allocation collision, copy, read-overwrite, and protection tests:
  **44** checks pass, all four guests exit zero.
- Native UIKit fixtures on **iPhone and iPad A16** simulators: status-bar and
  rotation-ownership cases pass for **SDK 2, 7, and 11** (12 runs). Hidden and
  visible bars, all four orientations, explicit ignore requests, argument/result
  preservation, and the SDK-11 negative control are covered. These are native
  iPad controls, not a retest of every installed iPad game.
- Compatibility-off/on compile checks, host build, aggregate app build, and
  `git diff --check` pass.

Evidence is under `tmp/doodle-road-20260929/`, notably `native-legacy-bounds.asm`,
`truck1-fixed-layout.log`, `truck2-fixed-layout.log`,
`truck2-fixed-right-layout.log`, `truck2-sdk11-settled.log`,
`road-device.ips`, `road-candidate-watch3.log`, `vm-remap-guest-final.log`,
and the phone/iPad native-regression logs. Early SDK-11/debugger attempts that
stopped before runtime loading are not the settled control above.

Original simulator game settings and saves are restored; test saves are retained
beside the evidence. Temporary app/runtime symlinks and fixture installations
are removed. Debuggers detached; no Mac keyboard/mouse automation was used.
