# Portrait-canvas research follow-up — 2026-09-29

Research only, using the runtime/code baseline at `6b5f88f` on `dev`. The earlier
experiment remains on `codex/portrait-canvas` (`87229ff`). No production hooks or
build flags were changed in this pass.

## Main result

There is a substantially smaller, promising route: **publish a portrait-only
supported-orientation mask to the real scene client**, rather than only changing
the initial decoded scene orientation or controller orientation getters.

In a standalone native SDK-7 fixture, an explicit
`FBSScene -updateUIClientSettingsWithBlock:` transaction setting
`supportedInterfaceOrientations = UIInterfaceOrientationMaskPortrait` kept the
system scene portrait through both landscape device orientations and a
background/rotate/resume cycle. This also worked with the original prototype's
four hooks entirely compiled out. The game-like view retained its own +90°
transform, and native device-orientation notifications still reported both
landscape orientations.

This is **not yet a production-ready replacement**. A live COD experiment held
the scene portrait too, but exposed a separate Classic Mode geometry problem.

## What the previous approach missed

The earlier `FBSSceneParameters -initWithXPCDictionary:` hook changes the
application's decoded initial scene/client orientations. The controller policy
hooks do not cover a rootless game that adds its render view directly to a
window. In the fresh rootless reproduction, the published client mask still
allowed landscape (`24`), and later system settings changed the scene to
landscape while the old window stayed 320×480.

Hooking `UIMutableApplicationSceneClientSettings` setters alone did not seed an
already-present mask. Its value remained `24` until an explicit outgoing update
changed it to `2`. Reading back the effective client settings is essential;
installing a setter hook is not evidence that the existing policy changed.

LLDB also confirmed this distinction on this iOS 27 simulator:

- `UIWindowScene -_internalInterfaceOrientation` uses client orientation when
  **host settings** enable device-orientation events; otherwise it uses host
  orientation.
- That host field is not the same as the similarly named **client** field.
  Forcing the client field off did not fix the escape.
- A public `requestGeometryUpdateWithPreferences:errorHandler:` call failed
  with `UISceneErrorDomain` code 101 while the effective mask still allowed only
  landscape. Explicitly publishing the portrait mask resolved this rejection.
  The successful minimal test did not need a public geometry request at all.

Evidence: `orientation-2.log`, `setters.log`, `client-policy.err`, and
`client-seeded.out` under `tmp/portrait-research-20260929/`.

## Preserve the old game's orientation model

“Old SDK sees portrait” needs qualification: old screen/window coordinates can
be portrait-based while the physical device and requested game orientation are
landscape. These are different states. Apple's coordinate-space documentation
describes the change to interface-oriented screen/window coordinates in iOS 8.
[Apple: UICoordinateSpace](https://developer.apple.com/documentation/uikit/uicoordinatespace)

The useful target is therefore:

- System-hosted scene: portrait, so the compositor does not turn it again.
- Legacy window/drawable: retain the engine's expected geometry.
- Engine transform and landscape status-bar requests: leave them alone where
  possible.
- Physical orientation notifications and motion input: do not spoof portrait.

The mask-only fixture retained landscape `statusBarOrientation` values 3/4
while the scene remained 1. It needed neither a status-bar setter override nor
a forced client `interfaceOrientation = portrait` value. This is a better fit
for engines that own their drawing rotation than forcing every orientation API
to report portrait.

## Standalone experiments

iPhone 17 Pro Max, iOS 27 simulator. Native ARM64 fixture with an SDK-7 Mach-O
load-command value, landscape-only Info.plist/controller, and a manually rotated
label. No LiveContainer or ARM32 emulator in these fixture runs. Rotation and
Home were sent through an isolated idb companion; no Mac keyboard/mouse input.

| Probe | Settled result |
| --- | --- |
| Fresh build of the original four-hook prototype, rootless | Escapes to landscape. |
| Extra client orientation/mask setter hooks, without publishing the initial mask | Mask stays landscape; escape remains. |
| Also force client device-orientation events off | Escape remains; not a solution. |
| Override scene `_currentlySupportedInterfaceOrientations` only, plus original prototype | Effective published mask stays landscape; request still rejected. |
| Explicit outgoing portrait mask/orientation update, with original prototype | Holds portrait through rotation/resume. |
| Same outgoing update, original prototype disabled | Holds portrait; no extra setter hooks required for this bounded run. |
| Publish only the portrait mask, no prototype hooks or geometry request | Holds portrait and preserves subsequent landscape status-bar requests. |
| Final reduced candidate: seed the mask plus one mask-setter override; original prototype disabled | Both rootless and rooted runs pass, 56 checks each, zero failures. |

The final checks cover live scene, portrait host orientation, portrait scene
bounds, portrait window bounds, published mask, and preserved engine transform.
The policy still allowed real physical orientation changes. Classic window
safe-area insets were zero. The unhooked cold launch briefly reported landscape
before the outgoing update settled: **startup timing/flash is not solved** by
this did-finish-launching experiment.

Evidence: `final-rootless-mask.out`, `final-rooted-mask.out`, corresponding
landscape/resume screenshots, `bare-mask-only.out`, and the disposable sources
`Probe.m`, `ResearchPolicies.m`, `build.sh`, and `run.sh`. Earlier flag-off runs
printed only two built-in checks per sample; their logged geometry, not those
counts, establishes their result. An initially reused stale fixture binary was
not used as the fresh baseline or as final pass evidence.

## COD real-engine probe and remaining blocker

COD Zombies used original SDK selection `0x20000`, Classic Mode, and the archived
four-hook runtime. Its game bundle was not reinstalled; the runtime was linked
temporarily. LLDB confirmed a nil root controller.

Before the outgoing update, the scene escaped to landscape with 480×320 scene
bounds and a 320×480 window. Publishing only mask `2` made the actual scene
portrait, and it remained portrait after the opposite landscape rotation and
background/resume. Physical orientation remained landscape. This was not just
an overridden orientation getter: screenshots changed to a portrait surface.

However, the scene/screen became **440×956**, while the game window remained
**320×480**, leaving the title artwork misplaced. The client `compatibilityMode`
still read **1**, so it is premature to say Classic Mode was simply disabled.
The cause of this host geometry renegotiation has not been isolated. Window
safe-area insets were zero; neither a universal home-indicator fix nor gameplay
correctness is established. The intro finished naturally; there was no touch or
gameplay test.

Evidence: `cod-mask.log`, `cod-after-right.log`, `cod-after-resume.log`,
`cod-before-mask.png`, `cod-mask-right.png`, and `cod-mask-resume.png`.
The first after-right snapshot's root/safe-area expressions failed to compile;
the after-resume snapshot corrected them and verified nil root/zero insets.

## New public orientation-lock API

iOS 26 adds `UIViewController.prefersInterfaceOrientationLocked`. Apple describes
it as a conditional preference: the scene must be centered, screen-sized, and
unoccluded, and the system can release the lock when those conditions change.
It is not a general hard-lock mechanism for arbitrary Classic Mode or iPad
windows. [Apple: prefersInterfaceOrientationLocked](https://developer.apple.com/documentation/uikit/uiviewcontroller/prefersinterfaceorientationlocked)

Native disassembly also shows that evaluating this preference looks for a root
controller and publishes an orientation-lock preference through scene client
settings. A rootless game has no such controller. The similarly named setter on
`_UISceneOrientationClientComponent` itself is a no-op on this runtime; it is
not a usable direct lock entry point. No new public-lock override was installed.
See `lock-policy.log` and `setters.log`.

## Window-only alternative discussed after the probes

Allowing the scene to rotate while retaining portrait backing coordinates for
only the game's main window is another viable direction to investigate. This
is close to the existing `LegacyRotation.mm` backing-layer repair, which selects
UIKit's legacy window-owned transform setup only during
`_configureRootLayer:sceneTransformLayer:transformLayer:`. It is not equivalent
to merely freezing the window's bounds or its orientation getter: COD already
had portrait window bounds while the scene rotated incorrectly.

The earlier OvenBreak diagnostic in `tmp/ovenbreak-orientation-diagnosis.md`
restored an inverse backing rotation and made the artwork upright without
changing the engine's own transform; clipping remained. A follow-up should
check whether the existing scoped backing hooks can support this model, with
rendering and touch conversions using the same window-to-scene transform.
Separate native windows could remain unaffected, but alerts presented inside
the game window need explicit coverage. A rotating scene would still control
the home indicator, so this does not move it to the portrait edge.

This alternative was reviewed against existing code and evidence, not newly
implemented or simulator-tested in the follow-up discussion.

## Next implementation experiments

Investigate the narrower window-only approach above before expanding the
scene-wide prototype. If a full portrait scene is still required, the following
constraints apply to the outgoing-mask approach.

Keep this opt-in and phone-only initially. Isolate one scene-policy unit that
publishes the portrait mask early enough and maintains it when UIKit recomputes
the supported mask. Do not add orientation-getter spoofing, device-event
suppression, manual window transforms, or safe-area-zeroing hooks.

Before replacing the branch prototype, resolve COD's scene/window size split
and identify the earliest safe publication point. Then test cold portrait and
landscape starts, intro presentation/dismissal, both rotations, resume, native
alerts, and touch alignment in COD, Doodle Truck 2, and Asphalt. The prior
engine-rendering failures remain unproven; a reliable scene lock alone does not
guarantee every engine renders correctly. Native iPad behavior should remain
unchanged until it has separate coverage. No iPad or real-device test was made
in this research pass.

## Cleanup

COD metadata and saves were restored and verified against the pre-launch backups.
The test save was retained in the artifact directory, the temporary runtime link
and disposable probe app were removed, and the simulator was returned to
portrait. See `cleanup.log`. All LLDB sessions detached; the task's isolated
companion was stopped after cleanup. Normal build products were untouched.
No production changes or pushes were made.
