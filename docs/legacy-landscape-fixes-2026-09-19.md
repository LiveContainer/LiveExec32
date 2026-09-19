# Legacy SDK landscape fixes — 19 September 2026

Partial fixes implemented and verified: Minecraft's cold-start inversion and Ninjago's sideways/clipped menu. The 13-game retest and native regression matrix are complete. Remaining failures are explicitly listed below.

## Scope and method

- iPhone 17 Pro Max simulator, iOS 27.0; existing LiveContainer installation and game data.
- Original ARM32 SDK override; SDK 2.0 fallback where the executable records no SDK. Classic Mode enabled throughout. Existing orientation-lock settings retained.
- Launch through `livecontainer://livecontainer-launch`, not a direct selected-app launch.
- Cold landscape-left launch, idb landscape-right, then landscape-left. No Mac keyboard/mouse input and no touch tests or prompt dismissal.
- Screenshots precede the final debugger geometry/SDK check. Diagnostic experiments are kept separate from final retests.
- Scope is the 13 games with a visible legacy landscape scene in the preceding comparison, including Doodle Truck as a control. Unrelated startup crashes from the 28-game comparison are not claimed fixed here.

Baseline: [legacy/SDK 11 comparison](landscape-sdk-comparison-2026-09-18.md).
Local evidence: [test directory](../tmp/legacy-fixes-20260919/).

## Shared corrections

1. Separate deprecated orientation-policy queries from the pre-iOS-8 rotation lifecycle. A guest controller using the iOS 6 `supportedInterfaceOrientations` / `shouldAutorotate` policy still needs old backing coordinates and `willRotate` / `didRotate` notifications. Ninjago's `UnityDefaultViewController` has exactly this shape and was previously excluded.
2. Synchronize the legacy window backing around the native window orientation update **for explicit guest root controllers**. Update the window extent before the renderer is resized, then refresh its backing transform afterwards. Previously a scene could rotate the content without updating that backing, or apply the scene-size delta again through autoresizing. Rootless, manually rotated renderers are excluded from this new refresh hook.

The implementation stays in `HostFrameworks/UIKit/LegacyRotation.mm`, under the existing effective-SDK-before-8 gate. It adds one shared window-update hook, reuses the existing lifecycle/configuration hooks, consolidates deferred attachment handling, and adds no game names, SDK spoofing changes, fixed screen sizes, or renderer-transform heuristics. Native/unregistered controllers and modern policy decisions remain outside legacy policy querying.

## Important remaining simulator observations

Classic Mode is requested and its saved metadata is unchanged, but this simulator can change `UIScreen.bounds` from 320×568 to 440×956 during startup/rotation. That remains a separate observation, not a physical-device conclusion. Complete, upright content does not imply a stable Classic Mode viewport or validated gameplay.

Minecraft's inversion is corrected in the repeated final retest, but its white strip and small left-aligned drawing area remain. Ninjago's content is upright and complete after return rotation, but its displayed size/aspect changes with the simulator's viewport. Its oversized returned Unity view changed from 1344×506 in the intermediate lifecycle-only candidate to 956×386 after fixing resize order.

`UIDevice.orientation` can also remain unknown or stale while idb changes the scene orientation. These checks exercise the simulator's scene/compositor path, not physical accelerometer behavior.

## Per-game final retests

Every image link is a clean launch of the final scoped runtime, with cold / right / returned-left captures in that order where the process survived. “Fixed” below refers only to the stated visible defect, not complete gameplay or device compatibility. Ninjago and Jetpack were given 60 seconds before the first capture; other games 30 seconds. No blocking prompt was dismissed.

| Game | Legacy SDK | Result | Remaining limitation / evidence |
| --- | --- | --- | --- |
| Minecraft PE 0.6.1 | 6.0 | **Cold-start inversion fixed**; menu upright through both turns. | White top strip and small, left-aligned renderer remain. [Captures](../tmp/legacy-fixes-20260919/01-scoped-final/sheet.jpg) |
| LEGO Ninjago: The Final Battle, build 5 | 6.1 | **Sideways/tall clipping and return-rotation clipping fixed**; complete loaded menu on all three captures. | Viewport size/aspect still changes. [Captures](../tmp/legacy-fixes-20260919/02-scoped-final/sheet.jpg) |
| Angry Birds Rio 1.6.1 | 6.1 | Upright menu throughout, but **clipping unresolved**. | Logo cropped, especially after return expansion. Controls remain distributed across the background. Baseline had a different reward screen, so this is not a strict control-layout comparison. [Captures](../tmp/legacy-fixes-20260919/03-scoped-final/sheet.jpg) |
| Doodle Truck 1.7.8 | 7.0 | **Control passes:** upright, complete, consistently sized menu throughout. | Fixed landscape orientation correctly retained. No gameplay input. [Captures](../tmp/legacy-fixes-20260919/04-scoped-final/sheet.jpg) |
| OvenBreak 2 1.32 | 6.1 | Upright loading screen throughout; no orientation regression seen. | Still at “Heating oven” during the observation window, in a small lower-left region. No loading fix claimed. [Captures](../tmp/legacy-fixes-20260919/05-scoped-final/sheet.jpg) |
| Jetpack Joyride 1.4.1 | 6.0 | **Unresolved:** loaded OpenFeint prompt upright initially and on return, inverted on the opposite side. | Return also expands the background and separates artwork/buttons. Repeated after the prompt fully loaded. [Captures](../tmp/legacy-fixes-20260919/06-scoped-final/sheet.jpg) |
| Mini Car Champion 1.0 | 2.0* | Upright menu throughout; no new orientation fix claimed. | Existing shrink/upper-right displacement remains. [Captures](../tmp/legacy-fixes-20260919/07-scoped-final/sheet.jpg) |
| Blaster Tank 1.5.4 | 2.0* | Upright Game Center connection-error prompt throughout. | Viewport shrinks then expands. Prompt untouched; gameplay not tested. [Captures](../tmp/legacy-fixes-20260919/08-scoped-final/sheet.jpg) |
| Angry Birds Lite 1.4.2 | 2.0* | **Unresolved:** sideways, clipped splash in all captures. | No menu reached; viewport changes size/position. Existing landscape lock retained. [Captures](../tmp/legacy-fixes-20260919/09-scoped-final/sheet.jpg) |
| Angry Birds 1.2.0 | 2.0* | **Unresolved:** Crystal prompt inverted in all three captures. | Viewport shrinks, then moves to upper-right. [Captures](../tmp/legacy-fixes-20260919/10-scoped-final/sheet.jpg) |
| Fruit Ninja 1.0 | 2.0* | **Unresolved:** OpenFeint prompt inverted throughout. | Return expands the background, displaces its contents right, and hides the buttons. [Captures](../tmp/legacy-fixes-20260919/11-scoped-final/sheet.jpg) |
| UNO 1.9.8 | 2.0* | **Unresolved:** sideways sound screen behind an upright firmware-warning alert, then process exits after the first right-turn command (~41 seconds after test start). | No return capture or debugger attach. Rotation timing is associated with the exit, but its cause is not isolated. SDK configured only. [Captures](../tmp/legacy-fixes-20260919/12-scoped-final/sheet.jpg) |
| Plants vs. Zombies 1.9.5 | 2.0* | Upright title screen throughout; candidate regression removed. | Existing shrink/upper-right displacement remains. [Captures](../tmp/legacy-fixes-20260919/20-scoped-final/sheet.jpg) |

`2.0*` is LC's existing fallback for a missing/zero Mach-O SDK, not a claim that the game was built with SDK 2.0.

## Rootless-policy investigation and rejected changes

- Fruit Ninja's OpenFeint prompt uses an `OFRootController` directly attached to a window with no root controller. Its legacy policy accepts orientation 3 (landscape-right) and rejects 4 (landscape-left), while the window/scene reports 4 and its view retains a +90° transform. The window has no native rotation clients. This is a concrete policy/backing mismatch, not a Mac-window focus problem.
- A disposable debugger experiment registered that controller through UIKit's existing rotation-client API, without adopting its view as the root. The prompt still inverted and lost layout on return rotation. That registration is **not** part of the patch.
- The first candidate refreshed rootless windows on every scene turn too. This introduced an opposite-side inversion in Plants vs. Zombies. Restricting the new hook to explicit guest roots removed that regression in the repeated three-capture test; its pre-existing viewport shift remains.
- No four-direction policy probing, automatic root adoption, fixed-size scaling, or per-game transform correction was added. Old Unity renderers can queue a manual turn even when their legacy policy returns `NO`, so speculative policy probes are unsafe.

Diagnostic evidence is under `11-rootless-probe`; captures 02–04 precede successful native-client registration, and 05–07 follow it. These are not final clean-launch results.

## Verification

- **13 game retests, 38 screenshots.** Effective SDK read back from the running process for 12 games. UNO exited before that inspection; its configured override is not presented as runtime-verified.
- Every game's `classicMode`, `spoofSDKVersion`, `LCOrientationLock`, and `LCClassicModeCache` was re-read and compared with the pre-test inventory, including absent keys. **All 13 restored; zero audit errors.** [Audit](../tmp/legacy-fixes-20260919/audit.json)
- Runtime build succeeded. Only the shared runtime was installed/re-signed; the LC-compatible launcher was preserved. Final shared-runtime SHA-256: `41fbb02b0f4b2e22a2483286610d38a583fbfa2a6b76186f5baf195ec18da2b0`.
- This pass changes only `HostFrameworks/UIKit/LegacyRotation.mm`, the two `test/uikit_legacy_rootless_rotation` fixture files, and this report. Earlier dirty crash/bridge fixes are preserved. No commit or push.
- The native fixture compiles the actual production rotation unit without the guest emulator. New coverage checks an iOS-6-style modern-policy controller with no deprecated policy override, before/after backing refresh order, rootless/native exclusions, and the SDK 8+ hook gate. Existing lifecycle, native veto, modal, deferred attachment, ownership, and replacement cases are retained.
- **78/78 native regression cases passed:** 13 cases each at SDK 2.0, 5.0, 6.1, 7.0, 8.0, and 11.0. The modern SDKs verify that the new hook stays disabled. [Final regression log](../tmp/legacy-fixes-20260919/regression-final.log)
- Reproduction: `sh test/uikit_legacy_rootless_rotation.sh --device 94D177DD-0AEE-41BF-B182-ED4FEAA28100 --keep`.
- `git diff --check` passed. LC and fixture processes are stopped; temporary fixture apps were uninstalled by the test script. Simulator returned to portrait and this run's isolated idb companion stopped. Other companions/processes were left alone.
- Per-game SDK settings are restored to their pre-test values, including any saved SDK 11 overrides; this report's fixes concern the tested **Legacy SDK** configuration.
