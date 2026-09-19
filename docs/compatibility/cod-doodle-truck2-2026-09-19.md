# COD Zombies and Doodle Truck 2 — Legacy SDK investigation

## Scope and environment

- iPhone 17 Pro Max simulator, iOS 27.0, device `94D177DD-0AEE-41BF-B182-ED4FEAA28100`.
- LiveContainer URL launches with Classic Mode enabled. Rotation and intro-skip input use an isolated idb companion; no Mac keyboard, mouse, or focus changes.
- Doodle Truck 2 **1.1.3**, Legacy Store copy [105505](https://legacystore.app/ipa/105505), 46,047,873 bytes, SHA-1 `4cc6e1f27c3d5858e1d25eed37e7bf0193475283`. Copied only the app bundle; LC generated `LCAppInfo.plist` and a data container successfully.
- COD Zombies **1.5.0**, already installed. Its binary has no SDK version, so the Legacy test uses SDK 2.0. Doodle Truck 2's binary declares SDK 6.0; both that version and LC's automatically selected SDK 2.0 are tested.
- Evidence is in `tmp/orientation-cod-truck2-20260919/` (local, untracked game binaries/screenshots).

## COD startup crash

The reproducible crash was **not a pathname being copied past the stack**. The faulting guest routine at `0xbb0e6` repeatedly reads a byte from a serializer and copies it into a stack string. The destination filled with `0x04` until it crossed the stack boundary; the serializer's file handle was null and its filename was `console.bin`.

Tracing guest file opens found a stale legacy bundle alias:

`<COD data>/LiveExec32.app` pointed into the deleted LC container `706A6D88-1BB3-48F5-BE26-5DB1121DCE76`, rather than the current container `348B4423-27D2-437D-808D-9FB140940132`.

Preserved the broken symlink as `COD.stale-LiveExec32.app.symlink` in the evidence directory. On the next launch the existing bootstrap code created the valid relative alias `../../../Applications/com.activision.callofduty.app`. No game binary, save data, or production filesystem hook was changed. No shorter-path relocation was needed or performed.

With this alias repaired, COD survives startup. Before the orientation fix its intro was black in this simulator; with the final candidate the video is visible but small and offset. One isolated idb tap skips the intro/title and reaches the main menu. This establishes that the stale alias caused the observed startup failure, not that every possible COD crash is fixed.

Evidence: `cod-crash-memory.log`, `cod-alias-repair.json`, `cod-repaired-alias/`.

## COD orientation fix

After skipping the intro, COD's title screen is sideways and clipped. The app uses a plain rootless window containing a `MainController` view and guest `MainView`/`GLView` descendants. `MainController` does not supply the old rotation-policy method. The window still has portrait bounds, but UIKit's scene-era backing layers retain landscape bounds and no inverse rotation.

A scoped debugger experiment running UIKit's existing legacy backing setup made the same live title screen upright and fully visible. The experiment restored both temporary method implementations immediately; it did not change the game renderer's transform.

The production change separates rootless controller discovery for **backing geometry** from discovery for **old rotation-policy queries**. Any registered guest controller can provide backing ownership, even without an old rotation-policy method. Such controllers receive backing refreshes on scene changes without old policy queries, synthetic rotation callbacks, or root adoption. Old-policy rootless controllers retain their existing renderer-owned turn lifecycle. No new swizzle, game-name condition, hard-coded angle, or scaling heuristic was added. SDK 8+ keeps this path disabled.

Changed sources:

- `HostFrameworks/UIKit/LegacyRotation.mm`

Regression fixture: `test/uikit_legacy_rootless_rotation.{m,sh}` adds a policy-free rootless controller case and exercises rootless modern-policy backing, queued refreshes, ownership restoration, and unregistered-controller exclusions.

An earlier view-only candidate was discarded after actual-game testing exposed the `MainController` owner in the responder chain. The final change does not register UIView classes or inspect view trees. The first 84-case matrix (`rotation-matrix.log`) concerns that discarded candidate and is not final-fix verification.

## Doodle Truck 2 device report

The user confirms that version 1.1.3 is upside down on their device with the latest build, after both portrait and landscape launches. **That device failure is not yet reproduced or fixed here.**

Before this pass's production change, the simulator was already upright with:

- original SDK 6.0: landscape-left cold launch, right turn, left return;
- LC's SDK 2.0: landscape-right cold launch, left turn, right return;
- SDK 2.0: portrait cold launch, which transitions to landscape.

The portrait launch eventually shows a clipped rating alert over an upright game. No rating/account action was selected. Classic viewport size changes after rotation are also visible; these are recorded separately from the reported inversion.

Geometry confirms an explicit guest `EventEAGLViewController` root, unlike COD's rootless controller. Consequently the new rootless-controller branch is not a claimed Doodle Truck 2 fix. Device model/iOS version has been requested to investigate the simulator/device difference.

Evidence: `truck2-baseline/`, `truck2-sdk2-baseline/`, `truck2-portrait-baseline/`.

## Verification and handoff

- The new `manual-controller` fixture **fails against the pre-change source**: the root layer keeps landscape bounds and an identity transform. The final candidate passes this fixture without adopting the controller, changing its renderer bounds/transform, or introducing old rotation-policy calls. Baseline fixture uninstalled after the comparison. [Baseline log](../../tmp/orientation-cod-truck2-20260919/baseline-controller-run.log)
- Focused final-candidate checks: **9/9 passed** (manual controller, queued backing refresh, scoped ownership; SDK 2.0, 6.1, and 11.0). [Focused log](../../tmp/orientation-cod-truck2-20260919/controller-focused.log)
- **Full final-candidate matrix: 84/84 passed**, 14 cases each at SDK 2.0, 5.0, 6.1, 7.0, 8.0, and 11.0. The last two SDKs verify that the compatibility hooks stay disabled. Every fixture launch exited successfully; no failing assertions. [Final matrix](../../tmp/orientation-cod-truck2-20260919/controller-matrix.log)
- Final shared-runtime SHA-256: `f6ff72e15c3add5798ea47ff62c7bc63bce0d7550290157c8ef2993dc6064ede`. Built the shared framework only and preserved the LC-compatible dylib launcher.
- The shared-framework signature and launcher Mach-O signature verify individually. A separate strict verification of the entire LC-compatible app bundle returns `No such file or directory` even though the bundle exists; distribution/package signing is not certified by this simulator pass.

### Final-candidate game retests

All launches use LC's URL path with Classic Mode enabled. Screenshots are taken before debugger inspection; no temporary method overrides are involved. idb changes the simulator scene orientation, which does not validate physical-device accelerometer behavior. Changes in Classic Mode viewport size/position are recorded as simulator observations, per the requested scope.

| Game / SDK | Cold launch and both landscape directions | Remaining observation |
| --- | --- | --- |
| COD Zombies 1.5.0 / 2.0 fallback | **Upright main menu**, all menu options visible after intro skip; no startup crash. Runtime SDK read back as 2.0. [Captures](../../tmp/orientation-cod-truck2-20260919/cod-controller-fixed/) | Centered on the first side; viewport shifts to the upper-right on return. Not a complete gameplay/crash certification. |
| COD Zombies 1.5.0 / 2.0, portrait launch | Survives startup and intro skip; title upright in both subsequent landscape captures. [Captures](../../tmp/orientation-cod-truck2-20260919/cod-controller-portrait/) | Before the first turn the simulator screenshot remains portrait with landscape artwork rotated inside it. Return viewport shifts upper-right; status bar overlaps the title. Automatic portrait-to-landscape scene transition is not claimed fixed. |
| Doodle Truck 2 1.1.3 / original 6.0 | Upright menu throughout, matching the pre-change behavior. [Captures](../../tmp/orientation-cod-truck2-20260919/truck2-controller-sdk6/) | Viewport shrinks then expands; cold status bar remains sideways. Device inversion remains open. |
| Doodle Truck 2 1.1.3 / LC-selected 2.0 | Portrait cold launch transitions to an upright landscape menu; both turns remain upright. [Captures](../../tmp/orientation-cod-truck2-20260919/truck2-controller-sdk2/) | Viewport expands on return; no rating prompt in this particular retest. Device inversion remains open. |
| Minecraft PE 0.6.1 / 6.0 | Upright menu throughout; earlier inversion fix retained. [Captures](../../tmp/orientation-cod-truck2-20260919/minecraft-controller-control/) | Existing white top strip and small left-aligned renderer remain. |
| LEGO Ninjago / 6.1 | Upright loading screen at 30 seconds; complete upright menu on the right and returned-left captures. [Captures](../../tmp/orientation-cod-truck2-20260919/ninjago-controller-control/) | Existing viewport size/aspect change remains. |
| Doodle Truck 1.7.8 / 7.0 | Upright, complete, consistently sized menu; fixed landscape orientation retained. [Captures](../../tmp/orientation-cod-truck2-20260919/truck1-controller-control/) | No gameplay input. |
| Plants vs. Zombies 1.9.5 / 2.0 fallback | Upright title screen throughout; no return of the earlier opposite-side inversion regression. [Captures](../../tmp/orientation-cod-truck2-20260919/pvz-controller-control/) | Existing viewport shrink and upper-right displacement remain. |

All six runs in the control batch remained alive and restored their settings. SDKs in that batch were configured in metadata, not re-read through the debugger on every process. [Batch results](../../tmp/orientation-cod-truck2-20260919/retest-final-results.json)

- **Settings audit: 8/8 final runs passed**, covering six games. Re-read `classicMode`, `spoofSDKVersion`, `LCOrientationLock`, and `LCClassicModeCache` against the saved original plist, including absent keys. Saved SDK 11 settings were restored, so the game's current saved selection is not necessarily the Legacy setting used for this report. No active game-test state remains. [Audit](../../tmp/orientation-cod-truck2-20260919/audit-final.json)
- The production edit in this pass is limited to the two controller-discovery/backing-refresh changes in `LegacyRotation.mm`. Prior dirty changes elsewhere are preserved. Test fixtures and this report are updated; nothing committed or pushed.

- Cleanup verified: LC stopped, final regression/baseline fixture apps uninstalled, simulator returned to portrait, and only this run's isolated idb companion terminated. [Cleanup log](../../tmp/orientation-cod-truck2-20260919/cleanup-final.log)
- `git diff --check` passed. The earlier view-tree experiment left no changes in `UIKit.mm` or `LC32LegacyRotation.h`.

Reproduce the native regression matrix with:

```sh
sh test/uikit_legacy_rootless_rotation.sh --device 94D177DD-0AEE-41BF-B182-ED4FEAA28100 --keep
```

**Open item:** Doodle Truck 2's device inversion needs the affected device model, iOS version, and confirmation of its per-app SDK setting. The simulator's clean menu is not evidence that the device issue has been fixed.

## COD follow-up: black screen after skipping the intro

The user clarified the sequence: rotated splash, small lower-left intro, then black **after tapping to skip**. These are separate failure modes; the earlier orientation pass did not establish that mid-video skipping worked. Some early test taps did not interrupt the video at all, so those runs are not counted as successful skip tests.

The already-running black-screen process was using **effective SDK 11**, read back through LLDB. It was alive in the normal main run loop, not crashed. A stopped `MPMoviePlayerController` remained embedded over the game, with load state zero, NaN duration/time, and no active AVPlayer. Its URL resolved to the valid 20.7-second `videos/intro.mp4`; the repaired bundle alias was still correct.

Fresh, untouched launches reached the upright title with Legacy SDK 2 in both landscape directions and with SDK 11 on the right. All three had the small/offset video; SDK 11 also had a sideways/clipped splash. Thus SDK 11 alone does **not** explain the persistent black screen.

### Reproduction and cause

A later simulator-only tap, approximately 30 seconds after launch, reproduced the persistent black screen with **Legacy SDK 2**. After another 29 seconds the movie was still stopped and its opaque view still covered the renderer. COD's `S3EViewController` remained registered for the movie-finished notification. Manually delivering that notification with the user-exited reason caused COD itself to remove its movie view and reveal the upright title.

The iOS 27 native `-[MPMoviePlayerController stop]` disassembles to setting its internal player to nil. In the reproduced path it never completes the notification-driven cleanup that this guest expects. This is separate from the old serializer crash and does not require a path-length workaround.

Evidence:

- `cod-followup-running.lldb.log`, `cod-followup-movie-direct.log`: initial SDK 11 black-screen state.
- `cod-followup-legacy-natural/`, `cod-followup-legacy-right/`, `cod-followup-sdk11-right/`: untouched playback comparisons.
- `cod-followup-legacy-late-skip/`: reproducible Legacy black screen and successful notification experiment.
- `late-skip-inspect.log`, `legacy-skip-finish-experiment.log`, `native-movie-stop-disasm.log`: view ownership, observer registration, recovery, and native implementation.

### Compatibility change

`GuestFrameworks/MediaPlayer/MPMoviePlayerController+LC32Legacy.m` now supplies the missing completion when a guest stops an active movie. It still forwards native `stop`, defers notification until the guest's stop stack has unwound, and lets synchronous or immediately queued native completion win. Repeated/reentrant stop on an already stopped player and immediate restart do not manufacture another completion. The temporary observer is scoped to that movie and is removed before fallback delivery.

This is one guest-side method override, with no game-name tests, new host swizzles, or changes to the rotation hooks. The completion uses the existing [movie-finished notification and reason key](https://developer.apple.com/documentation/mediaplayer/mpmovieplayerplaybackdidfinishnotification); restoring missing stop completion is a compatibility decision established by the reproduction, not a claim that Apple's current documentation promises it for every stop.

- Host regression test: **61/61 checks passed**, compiling the real category against a deterministic native bridge. Covers absent/native synchronous/native queued completion, player identity, reason, stopped/paused/interrupted/seeking states, duplicate/reentrant stop, restart, another player's notification, deferred lifetime, and legacy controls. Run `gmake -C test check-mediaplayer-stop`.
- Rebuilt only the guest MediaPlayer shim. Final shim SHA-256: `577595d23296bee0d2c19c69cdab41249305473889c89116901b3e33a1a3a7a2`. Original shim preserved as `MediaPlayer.before-skip-fix`.
- Preserved the user's newer shared runtime, SHA-256 `c40a931ec64c4399658992fd9a85ceda7a4e3f4cc9a9380d14958089cc7e79a7`, and LC-compatible dylib launcher. The earlier orientation runtime hash above identifies that earlier pass, not the follow-up build.

### Final-build verification

The final-build tests add a native, process-local notification counter before the intro. They do not replace movie methods or inject completion notifications. For deterministic skip verification, the debugger invokes COD's **existing guest `S3EViewController.stop` method**, the same entry reached by the game's skip path; this is not a synthetic finish event. The live receiver's class is validated before calling it. This bypasses simulator hit-testing and is reported separately from physical tap coverage.

| Final build / test | Observed outcome |
| --- | --- |
| Legacy SDK 2, right, guest stop during the intro | Upright title by the 8-second post-stop capture, still alive after another 30 seconds. **Exactly one finish, reason 2 (user exited)**. No movie proxy/player view remains. Effective SDK read back as 2.0. `cod-stop-final-legacy-stop-entry/`. |
| SDK 11, right, guest stop during the intro | Upright title by the 8-second post-stop capture and on the final capture. **Exactly one finish, reason 2 (user exited)**. No movie view remains. Effective SDK read back as 11.0. `cod-stop-final-sdk11-stop-entry/`. |
| Legacy SDK 2, left, untouched intro | Upright title. **Exactly one finish, reason 0 (natural end)**. No movie view remains. Effective SDK 2.0. `cod-stop-final-legacy-natural/`. |
| Legacy SDK 2, right, two counted idb-tap runs | Both reached the title with one reason-0 notification; these taps did **not** interrupt playback and are not counted as successful skip tests. `cod-stop-final-legacy-right/`, `cod-stop-final-legacy-tap-counted/`. |

An earlier candidate's late idb tap also recovered to the title, unlike the baseline's persistent black screen, but lacked a completion-reason counter. The deterministic final-build result above establishes the actual stop-path behavior. A diagnostic attempt to find the guest controller through `NSNotificationCenter.debugDescription` faulted inside the debugger expression; that test was aborted and restored, not counted as a pass. The successful check instead reads COD's known guest controller slot through the emulator's page table and validates its class.

The public-symbol audit passes: **1,563/1,563 required UIKit/graphics/media symbols present**, including all 112 required MediaPlayer symbols. [Audit](../../tmp/orientation-cod-truck2-20260919/movie-stop-public-symbols.log)

**Remaining:** this change fixes the reproduced stop/cleanup path, not the small lower-left intro layout, SDK 11's sideways/clipped splash, portrait-launch scene behavior, or the reported physical-device inversion. No new orientation patch is included in this follow-up. Natural Legacy landscape launches remain upright in the simulator. The saved SDK selection is restored after every test, rather than silently switched to Legacy.

The LC-compatible launcher signature verifies. The preserved user-built shared runtime is unsigned; this pass does not certify distribution signing or silently re-sign that unrelated binary.

No production changes beyond the guest MediaPlayer category were added during this follow-up. Its source, regression test, test build rule, and this report are saved locally; nothing committed or pushed.

**Cleanup/settings audit: 15/15 run records restored their original values**, including absent keys, for `classicMode`, `spoofSDKVersion`, `LCOrientationLock`, and `LCClassicModeCache`. This is a settings audit, not 15 successful game tests; it includes the aborted diagnostic. COD's saved SDK 11 selection is retained. LC is stopped, no active test record remains, the simulator is back in portrait, and only the validated isolated companion (PID 65664) was terminated. Other user-owned companions/debuggers were left alone. Final `git diff --check` passed. [Audit](../../tmp/orientation-cod-truck2-20260919/audit-followup.json)
