# Sheep Mania and Flight Control HD fixes

2026-09-28, based on `266f856`. Sheep Mania drawable replacement and Flight
Control HD's iPad-on-phone input/canvas fixes implemented. Simulator verification,
not a real-device retest or an all-games/iPadOS certification.

## Setup

- iPhone 17 Pro Max / iOS 27 simulator, LiveContainer URL launch, Classic Mode on.
- Original-SDK selection `0x20000`; `LC32_UIKIT_COMPATIBILITY=1` in the matched
  host/guest build. The modern-host UIKit adapter's runtime gate returns **0**
  with this SDK setting, independently of the build flag.
- Installed copies: Sheep Mania / PuzzleIslands **1.0.2** (minimum iOS **3.0**),
  Flight Control HD **1.07** (minimum iOS **3.2**). The reported 3.0/3.2 labels
  match minimum OS, not these binaries' versions; device-copy equality is unverified.
- LLDB and simulator-only idb input; no Mac keyboard/mouse interaction.

## Sheep Mania: fixed drawable replacement

The game reaches its menu internally, but `PMGraphics::layerChanged` allocates
fresh framebuffer/renderbuffer objects every time `layoutSubviews` runs. It
does not release the previous color buffer's attachment to the same `CAEAGLLayer`
and ignores a failed `renderbufferStorage:fromDrawable:` call. The replacement
has zero dimensions and an incomplete framebuffer; the last splash frame remains
visible.

The earlier investigation traced the second startup layout to native pre-iOS-10
trait propagation. The scene's secure-rendering trait update schedules layout;
no bounds change is required. SDK 10/11 avoid this particular startup trigger,
but manually requesting layout still breaks the unmodified game. Suppressing
the scene event would therefore hide the symptom, not repair replacement.

The existing EAGL storage hook now tracks guest drawable ownership per sharegroup,
using weak layer references. Only after native allocation fails, it can release
the same layer's known previous attachment and retry. It preserves the caller's
renderbuffer/framebuffer bindings and does not delete the old object. Deleting
or redefining a renderbuffer clears its record; unrelated sharegroups are not
searched. Malformed color-format requests do not release the previous owner.
There are no new UIKit hooks, game-name checks, private-flag writes, or SDK changes.

Original SDK now reaches the visible menu without debugger intervention.
Framebuffer status is `GL_FRAMEBUFFER_COMPLETE` (`0x8cd5`) both after natural
startup and after an additional ordinary layout. The latter replaces color
buffer 3 with 5, retains a complete framebuffer, and leaves `glGetError() == 0`.

## Flight Control HD: drawing/input coordinate mismatch

This iPad-only binary draws a **768 × 1024** logical interface, but its native
window, EAGLView, layer, renderbuffer and viewport are **320 × 480** under original
SDK. LLDB measured projection coefficients `2/768` and `-2/1024`, with translation
`(-1,+1)`. Rendering scales into the smaller drawable; input does not.

The Play tap reaches the intended guest view through `UITouch.locationInView:`
at approximately `(77.818, 385.455)`. Guest `processTouchEvent:withEvent:` converts
those floats directly to integer game coordinates, apart from an optional
orientation transform. There is no iPad/phone scale correction. The visible
button is around `(186.764, 822.303)` in the drawing coordinate space.

A debugger-only experiment changed the return coordinates for this guest view
to `x * 768/320`, `y * 1024/480`, leaving native UIKit's own queries unchanged.
A one-second press at the visible Play button then **entered gameplay**, with
the game still using original SDK and Classic Mode. Register readback confirmed
the corrected values. A shorter corrected tap did not activate Play, so the
one-second test is the successful evidence. A later Pause comparison was
inconclusive because the unattended game had already reached Game Over.

The source-policy cause is the coupling of `LC32ResolveLegacyCanvas` to
`LC32GuestUIKitLegacyCompatibilityEnabled()`. The latter disables modern-host
adapters below SDK 8 to avoid double rotation, but that also disables the iPad
canvas adaptation needed on a phone. The preceding SDK 11 control had a
768 × 1024 window and working Play input.

### Implemented canvas fix

The guest and host now share a separate iPad-on-phone canvas gate, independent
of the SDK-8 modern rotation gate. It requires compatibility to be enabled,
iPad-targeting bundle metadata, and a **native phone idiom**. A native iPad,
including a narrow iPad scene, is not classified as a phone merely by width.
The existing 768×1024 canvas container keeps rendering and UIKit hit testing in
one coordinate system; there is no global `UITouch` coordinate hook or game-name
check. Native iPad windows are not wrapped by this new path.

Original-SDK canvas containers use their already-rotated native root bounds,
not the modern scene-to-view conversion. The legacy rotation unit resolves the
container's guest controller for backing setup, policy queries and guarded
will/did callbacks. Automatic child rotation forwarding remains disabled to
avoid duplicate callbacks. An empty container during installation is explicitly
handled. SDK 11 retains the existing modern container behavior.

The iPhone simulator now accepts the visible Play button in portrait and
landscape without debugger coordinate modification. Cold landscape menus are
upright and fully visible. Rotation during a running round can still stretch
the fixed drawable; this is not a claim that every orientation transition is
fixed. The real-device brief zoomed-then-corrected startup was not independently
captured or certified fixed.

### iPad control and broader smoke tests

Used iPad (A16), iOS 27, `3FB9DBF4-A92A-469B-B2AB-66589F29AE2D`. Game assets and
executables were **symlinked**, not reinstalled or duplicated. Each iPad shadow
bundle has its own `LCAppInfo.plist`: sharing the phone's cached Classic Mode
value incorrectly makes the iPad report the phone idiom and a 320×480 screen.
LiveContainer's native classifier returned 14 for FlightCtrl/PvZ HD/OvenBreak,
and 1 for Sheep Mania. These were test-only per-device settings, not a source
change to LiveContainer. Native FlightCtrl reported idiom 1 and canvas gate 0.

| Control | Result / limit |
| --- | --- |
| FlightCtrl, iPhone, original SDK | Visible Play works with the logical iPad canvas; landscape Play also enters gameplay. |
| FlightCtrl, iPhone, SDK 11 | Portrait Play still enters gameplay. |
| FlightCtrl, native iPad, original SDK | Portrait menu and Play work without the phone container. Rotation leaves some content sideways; the pre-change runtime reproduces it. |
| FlightCtrl, native iPad, SDK 11 | Portrait Play enters gameplay; no phone-canvas wrapper required. |
| Sheep Mania, iPad, original SDK | Passes splash and reaches visible Play/Help menu. Phone-compatibility viewport can be stretched; not a native-iPad geometry pass. |
| PvZ iPad Chinese 1.9.11, iPhone, original SDK | Reaches upright Tap to Start artwork; no gameplay/input certification. |
| PvZ iPad Chinese 1.9.11, iPad, original SDK | Startup fails at `UIWindow _finishedFirstHalfRotation:context:`. The pre-change runtime fails with the same selector. |
| OvenBreak 2, iPad, original SDK | Reaches Heating oven; sideways output and loading remain outside this fix. |
| OvenBreak 2, iPhone, original SDK | Reaches Heating oven; clipped loading artwork remains, not a gameplay pass. |

The pre-change control is `tmp/sheep-fix-20260928/Runtime.app` (includes the
already-tested Sheep drawable fix, but not these UIKit changes). Evidence is in
`tmp/ipad-canvas-20260928/`: `pad-corrected-geometry.log`,
`flight-clean-play.png`, `flight-v4-right-play-portrait-hid.png`,
`flight-phone-sdk11-play.png`,
`flight-pad-v4-left-settled.png`, `flight-pad-baseline-rotation.png`,
`flight-pad-sdk11-play-final.png`, `sheep-pad-settled.png`, `pvz-phone-final.png`, and
`pvz-pad-baseline-error.plist`. Early `pvz-phone-original.png`/Oven phone attempts
were invalid: a temporary debugger-launch selection selected FlightCtrl instead.
Those keys were removed and the affected smoke tests repeated
(`pvz-phone-final.png`, `oven-phone-final.png`). A final clean original-SDK
FlightCtrl launch and visible Play tap also entered gameplay
(`flight-clean-play.png`).

The native rotation fixture now covers empty/wrapped controllers, exact-once
legacy callbacks, guest-context suppression, and backing refresh before/after
the wrapped client update, alongside native-controller negative controls.
SDK 2 and SDK 11 ownership/lifecycle runs pass (288 PASS lines including
suite summaries, no FAIL), and the compatibility-off/on compile checks pass.
Guest installation and aggregate app rebuild succeed.

## Validation and evidence

- Host and aggregate app builds pass; drawable and full GL guest tests build.
- Dedicated drawable tests pass **105 checks** across ES1/ES2/ES3: replacement,
  resize, explicit
  release, shared contexts, invalid format, deletion/name reuse, offscreen
  storage redefinition after explicit drawable release, and cross-sharegroup
  rejection. Redefining still-attached layer storage is rejected by native EAGL
  on this simulator; the test uses the required release first.
- The broader GL suite retains four unrelated failures also reproduced with
  the unmodified host: `ES1-texture-parameter-fixed-roundtrip`,
  `nested-shader-source-copyback`, `shader-source-copyback`,
  `sync-64-bit-state-copyback`. It is not an all-green suite.
- OpenGLES symbol audit passes for 443 public functions.

Local evidence is retained under `tmp/sheep-fix-20260928/`:
`sheep-original-fixed.png`, `sheep-fixed-lldb.log`, `drawable-redefinition-final.log`,
`opengles-final.log`, `opengles-baseline.log`, `flight-initial-probe.log`,
`flight-disassembly.txt`, `flight-unscaled-tap.png`,
`flight-scaled-long-press.log`, and `flight-scaled-long-press.png`.
The initial automatic touch probe was invalid and restarted; use the final
long-press log for the successful counterfactual, not the initial probe's
zero-valued register writes. Earlier causal traces are in
`tmp/sheep-originalsdk-20260928/` and `tmp/sheep-layout-20260928/`; historical SDK
comparisons are in `tmp/sheep-flight-20260927/regression-investigation.md`.

The four iPhone games' original metadata and saves were restored and verified.
The iPad's test-created save folders were moved into the evidence directory;
temporary game/runtime symlinks on both simulators were removed. Original app
bundles were not removed or reinstalled. Test saves and evidence remain
available; cleanup verification is in `tmp/ipad-canvas-20260928/cleanup.log`.
Task LLDB sessions detached/exited, and only the two task-owned idb companions
were stopped. Unrelated debugger/companion processes were left alone.
No changes were pushed.

## iOS 15 follow-up: white drawable, 2026-10-03

Sheep Mania / PuzzleIslands 1.0.2 on the iPhone 6s Plus (iOS 15.4.1),
standalone original-SDK launch, had a separate first-allocation failure:
`renderbufferStorage:fromDrawable:` reported `invalid property values`, with
zero renderbuffer dimensions and `GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT`
(`0x8cd6`). The only visible window contained the game's EAGLView; no Game Center
presentation remained over it. Music and the render loop continued.

iOS 15 EAGL compares color-format values with its native constant objects by
identity. Our existing normalization substituted the correct constant, but
Core Animation retained the old properties dictionary because its replacement
compared equal by value. The stored RGBA8 string still belonged to the guest
bridge. In-process tracing confirmed that setting the canonical dictionary
again failed, while clearing it before setting the same dictionary succeeded.
The retained-backing value was already the native `__NSCFBoolean` and stayed
enabled in the successful test; removing it was not necessary.

The existing storage hook now clears the properties dictionary only when
normalization changes the color-format object, then installs the normalized
properties. No new swizzle, game-name check, SDK switch, or per-frame work was
added. The diagnostic game run reached a complete framebuffer (`0x8cd5`), valid
414×736 storage/viewport, successful presents and no GL errors through sampled
frame 1200. The user confirmed rendering resumed.

`test/opengles_drawable_properties.m` loads the built host framework and invokes
its actual normalization hook with a storage sink and real CAEAGLLayers. It
checks distinct-but-equal RGBA8/RGB565 strings, unchanged canonical dictionaries,
unrelated properties, invalid formats, nil drawables and one backend call per
request. This property test does not require a GPU or claim to test rendering.
The old iOS 15 framework reproduces stale identity (`--expect-stale`); the fixed
framework passes on iOS 15 and the iPhone/iPad iOS 27 simulators. Run with
`sh test/opengles_drawable_properties.sh --device UDID /absolute/path/to/LiveExec32Shared`;
`--platform iphoneos` builds a signed device probe without installing it.

The normal framework (UUID `E4145446-2676-3FB2-86AE-374C3A3632D4`) replaced the
temporary diagnostic build on the 6s. Local evidence is under
`tmp/sheep-ios15.EuLbZv/`: `window-trace3.log`, `window-trace5.log`,
`frame300-trace5.png`, and the simulator property-regression logs.

### Clipping resolved by disabling TrollPad

The user reports cut-off content after rendering resumes. The standalone
window and EAGLView expand from their archived 320×480 bounds to 414×736, while
the engine hard-codes `glScissor(0, 0, 320, 480)` in `PMGraphics::rendererBegin`
and uses 480 in `setClip`'s Y conversion. The larger viewport therefore scales
the drawing beyond its unchanged scissor region. A cold-launch attempt with
LiveContainer's `__ActivateAsClassic = 1` option still yielded 414×736 on this
device; its completion timed out despite starting the process. No global GL
coordinate/input patch or persistent launch setting was applied.

The device screenshot command supplied by the user subsequently confirmed the
menu is clipped across its top and right edges (`sheep-device-cutoff.png` in
the same evidence directory), not just surrounded by unused margins. The
screen also has an iPad-style multitasking control. `TrollPadSB` and `TrollPadUI`
are installed on the 6s; the local TrollPad source forces portrait applications
to be Medusa-capable and enables the multitasking control. The user subsequently
disabled TrollPad and confirmed the clipping disappeared with the same runtime.
No additional canvas, scissor or touch-coordinate fix was needed. The agent did
not change tweak settings or restart SpringBoard.

The earlier missing delayed-presentation selector repair remains separate.
Previously reported Game Center notification/relaunch crashes are not certified
fixed by this drawable change.

### Intermittent Play-button audio crash

After disabling TrollPad, the user reported one crash on Play, then a successful
second attempt without a runtime change. `PuzzleIslands-2026-10-03-100704.ips`
and `play-crash.old.log` in the same evidence directory identify a separate
guest SIGSEGV: a 16-bit read from `0x1c` in
`PMAudioModulePlayer::UpdateTick()`, reached through `Update()`,
`PMAudioDriver::UpdateInternal()` and the game's audio pthread.

The installed ARMv6 binary's tick loop reloads the current module from
`player + 0x20` and reads its 16-bit channel count at `module + 0x1c`
(`0x9f322`–`0x9f328`). Its earlier null check is in `Update()`, before the tick
call. The stop path clears that same module field. The log also captures
another guest callback halted in `PMAudioStreamProxy::Stop()` with its caller
in `PMAudioStreamPlayer::StopAll()`. This strongly suggests overlapping audio
stop/update operations during the Play transition. It does not yet establish
whether native guest parallelism exposes an original game race or a runtime
synchronization defect; the conflicting write has not been captured live.
No audio workaround or scheduling change has been applied. The successful
retry is not a regression pass for this intermittent failure.
