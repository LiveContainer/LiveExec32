# Landscape game SDK comparison — 2026-09-18–19

Status: **complete**. All 28 main comparisons, the longer Ninjago confirmation,
and the final restoration audit are finished. Each game was run sequentially with its
legacy SDK and SDK 11. **Classic Mode is enabled in both**, as requested.
This is a startup/orientation comparison, not a gameplay or touch certification.

## Main findings

- **Do not apply SDK 11 globally on the strength of this test.** It avoids the
  captured legacy inversion in Minecraft and Jetpack's OpenFeint prompt, but
  introduces an inversion in Plants vs. Zombies 1.9.5 and makes Mini Car
  Champion sideways/clipped.
- Clear **180° inversions** were captured in legacy mode for Minecraft,
  Jetpack Joyride's prompt, Angry Birds 1.2.0's Crystal prompt, and Fruit
  Ninja's OpenFeint prompt. SDK 11 captures show inversions in Plants vs.
  Zombies 1.9.5 and the Chinese iPad edition. These are six titles, not six
  claims about physical-device behavior.
- SDK 11 improves observed startup survival for Real Racing 1.27, SPY Mouse,
  and the Chinese iPad PvZ edition, and survives UNO's tested rotation cycle.
  Rendering/layout problems or untested gameplay remain. Angry Birds Lite
  reaches a later startup screen with SDK 11, but timing is not controlled
  tightly enough to call that a confirmed loading fix.
- Ninjago's longer, loaded-menu repeat confirms that SDK 11 avoids legacy's
  sideways/clipped menu, but its viewport still shrinks and expands through
  the rotation cycle. It is not a stable-layout pass.
- Black output remains in Asphalt 5, JellyCar, and Road Warrior. OvenBreak 2
  remains on “Heating oven.” These retain the requested simulator-only
  interpretation; slow loading is not proof of a permanent hang.

Main-sweep accounting: **28 games, 56 completed SDK runs, 127 screenshots**.
The runtime SDK query matched the configured value in **32 runs**. Another
**22 runs exited** before inspection (19 before the startup capture, three
after the first rotation); **two Road Warrior runs** retained a PID but stopped
at a native breakpoint before SDK inspection. Seventeen games have no recorded
SDK and therefore use the clearly marked `2.0*` legacy fallback. No game is
certified fully playable by this no-touch test.
The separate Ninjago confirmation adds two verified runs and six screenshots:
**58 usable runs and 133 screenshots in total**, excluding interrupted attempts.

## Controlled setup

- iPhone 17 Pro Max simulator, iOS 27.0; LiveContainer
  `com.kdt.livecontainer.UU7W52U79B`; LiveExec32 checkout `1f79917` plus the
  existing, uncommitted fixes described in
  [the issue-triage report](issue-game-triage-2026-09-18.md). The runtime is not
  rebuilt or changed between these comparisons.
- Launch through `livecontainer://livecontainer-launch` with each existing app
  bundle and data-container UUID, after terminating the previous LC process.
  No direct selected-app launch that could bypass Classic Mode activation.
- Legacy means the original ARM32 Mach-O SDK, when recorded. If absent/zero,
  use LC's nonzero **iOS 2.0 fallback**, explicitly marked `2.0*` below. This
  is not a test of an exact zero-valued SDK. The other setting is SDK 11.0.
  These are LC `spoofSDKVersion` settings on the **same app binary**, not two
  apps rebuilt using different Xcode SDKs.
- `classicMode=true` in both runs. Preserve each game's existing cached Classic
  Mode option and orientation lock; only the SDK changes between its two runs.
  Classic options differ between games, so comparisons are **within a game**.
- Use isolated idb companion 1.5.7, bound to simulator UDID
  `94D177DD-0AEE-41BF-B182-ED4FEAA28100`. Send `LANDSCAPE_LEFT` before launching,
  wait approximately 35 seconds (or until exit), capture; if still present, send
  `LANDSCAPE_RIGHT`, wait 3.5 seconds, capture; send `LANDSCAPE_LEFT`, wait
  3.5 seconds, capture. There are no macOS mouse/keyboard actions or touch tests.
  Screenshot labels name the **requested idb direction**, not a measured
  physical `UIDevice.orientation` value.
- For surviving processes, inspect the two SDK globals and call
  `dyld_get_program_sdk_version()` with LLDB **after** all three screenshots.
  Early exits have only a configured SDK, not a runtime-verified SDK.
  Exit times below are rounded **observation bounds**, not exact crash times.
  PID presence alone is not a health check; native stops at inspection are
  called out separately, and no crash root cause is inferred from PID loss.
- Preserve existing saves. Temporary SDK/Classic Mode settings are restored
  after each game; original full plists are also saved as recovery evidence.

## Interpretation limits

- Slow loading, black frames, and rendering defects are **simulator
  observations**, not established physical-device defects. A 35-second startup
  bound cannot distinguish a slow loader from a permanent hang.
- idb rotation injects simulator orientation events. Earlier investigation
  showed that these can change the scene without matching `UIDevice.orientation`;
  this is not a physical sensor test. Screenshots are scene-oriented, so an
  upright capture does not by itself prove correct physical-device orientation.
- Existing orientation locks remain set to `1` on Minecraft, OvenBreak 2, and
  Angry Birds Lite. Fixed-orientation titles may legitimately ignore one side.
- Native opt-in, network, sound, and sign-in prompts are left untouched. No
  claim is made about gameplay behind those prompts or later crashes.
- Existing data is reused, and legacy is always tested first; startup state and
  network timing can therefore differ. Small timing differences are not treated
  as SDK regressions.
- The Mac slept during the first Fruit Ninja/UNO attempts; the simulator later
  shut down. Those delayed/timed-out attempts are preserved in directories
  ending `.interrupted-first-attempt` and excluded from the results. Testing
  resumed headlessly on September 19 with the same simulator and unchanged
  runtime. The launcher SHA-256 before/after the interruption is
  `e20fbe276ed84ccb51eb0873c0bb2a4c61ee9ea0d02ddd9c6ce199d9e5a9249d`.

## Results

`2.0*` indicates the no-recorded-SDK fallback described above. “Upright” refers
to the saved scene-oriented image, subject to the idb limitation above.

| # | Game / version | Legacy SDK | Classic option / lock | Legacy result | SDK 11 result | Comparison |
|---|---|---|---|---|---|---|
| 1 | Minecraft PE 0.6.1 | 6.0 | 2 / 1 | Cold-start menu is 180° upside down, displaced/clipped, with a white strip. Rotation makes the menu upright but leaves an undersized, left-aligned viewport; white strip returns on the last capture. | Cold-start menu is upright. Opposite rotation shrinks it to a centered viewport; returning left shifts it down/left. | SDK 11 avoids the observed cold-start inversion, but **neither mode passes viewport stability**. Both SDKs runtime-verified. [Images](../../tmp/landscape-sdk-20260918/01-com.mojang.minecraftpe/comparison.jpg) |
| 2 | LEGO Ninjago: The Final Battle, build 5 | 6.1 | 2 / unset | Title starts cropped into a tall viewport. Rotation makes the menu sideways, tiny, and clipped; returning left does not restore it. | Main sweep was partly still loading; final menu was upright and complete. Longer repeat confirms an upright, complete loaded menu throughout rotation, but viewport shrinks on the opposite side and expands on return. | SDK 11 improves orientation/clipping, **not viewport stability**. Both SDKs verified in both passes. [Main images](../../tmp/landscape-sdk-20260918/02-com.lego.ninjago.thefinalbattle/comparison.jpg), [loaded-menu repeat](../../tmp/landscape-sdk-20260918/02-com.lego.ninjago.thefinalbattle.loaded-menu-repeat/comparison.jpg) |
| 3 | Angry Birds Rio 1.6.1 | 6.1 | 2 / unset | Upright daily-reward screen. Opposite rotation shrinks the viewport; returning left enlarges the background while reward controls remain offset left. | Upright menu; viewport also shrinks on opposite rotation and expands on return. Initial sideways status-bar text disappears after rotation. | No 180° inversion, but viewport size is not stable in either mode. Different startup screens reflect reused save state; no prompt was dismissed. Both SDKs verified. [Images](../../tmp/landscape-sdk-20260918/03-b/comparison.jpg) |
| 4 | Doodle Truck 1.7.8 | 7.0 | 2 / unset | Complete upright, centered menu; stable in all three captures. | Complete upright, centered menu; also stable, but narrower than legacy (approximately 3:2 versus 1.89:1). | No captured inversion or rotation-induced clipping. **SDK-dependent aspect/scale difference** remains; this test does not establish which aspect is intended. A fixed landscape scene can normalize physical inversion in screenshots. Both SDKs verified. [Images](../../tmp/landscape-sdk-20260918/04-com.trinitigame.doodletruck/comparison.jpg) |
| 5 | OvenBreak 2 1.32 | 6.1 | 2 / 1 | Still “Heating oven” at the last screenshot (~45 s). Upright; opposite rotation shrinks the image and return shifts it to the lower-left. | Same loading state and viewport shift; minor aspect/size differences. | No observed SDK 11 cure for loading or viewport instability. Alive in both; bounded simulator observation, not proof of permanent hang. Both SDKs verified. [Images](../../tmp/landscape-sdk-20260918/05-com.devsisters.ovenbreakx/comparison.jpg) |
| 6 | Jetpack Joyride 1.4.1 | 6.0 | 2 / unset | Initial Halfbrick image compressed into a horizontal strip. OpenFeint prompt appears upright on the opposite side, then becomes **180° upside down** and displaced on return left. | OpenFeint prompt upright in all captures. Returning left expands its background to the screen, with artwork at upper-left and buttons spread across the bottom. | SDK 11 avoids the captured prompt inversion, but prompt geometry still changes. No opt-in or gameplay test. Both SDKs verified. [Images](../../tmp/landscape-sdk-20260918/06-j/comparison.jpg) |
| 7 | Mini Car Champion 1.0 | 2.0* | 1 / unset | Menu upright. Opposite rotation shrinks it; return shifts it to the upper-right. | Menu is **90° sideways and heavily clipped** in a small viewport throughout the cycle. | SDK 11 is visually worse here; neither is a clean viewport pass. Both SDKs verified. [Images](../../tmp/landscape-sdk-20260918/07-com.spilgames.minicarchampion/comparison.jpg) |
| 8 | Blaster Tank 1.5.4 | 2.0* | 1 / unset | Upright Game Center connection-error screen. Viewport shrinks on opposite rotation, then expands/stretches across the screen on return. | Same upright connection-error screen. Viewport shrinks on opposite rotation and remains centered at that smaller size on return. | No inversion; SDK 11 avoids the final legacy stretch, but still changes size from cold start. Network prompt not dismissed. Both SDKs verified. [Images](../../tmp/landscape-sdk-20260918/08-com.trinitigame.blastertank/comparison.jpg) |
| 9 | Angry Birds Lite 1.4.2 | 2.0* | 1 / 1 | Sideways, clipped splash persists throughout captures. Rotation changes its size and moves it left. | Reaches upright menu with beta-warning prompt. Opposite rotation shrinks it, return enlarges it again. | Better startup progress observed with SDK 11, but timing/save warming is not controlled and viewport stability still fails. No prompt interaction. Both SDKs verified. [Images](../../tmp/landscape-sdk-20260918/09-a/comparison.jpg) |
| 10 | Angry Birds 1.2.0 | 2.0* | 1 / unset | Crystal opt-in screen is **180° upside down** throughout. Rotation shrinks it, then displaces it to upper-right. | Crystal screen and underlying menu are **90° sideways and clipped** throughout. | Neither mode has correct orientation/layout. SDK 11 changes the failure rather than fixing it. Prompt untouched; both SDKs verified. [Images](../../tmp/landscape-sdk-20260918/10-AB.eval/comparison.jpg) |
| 11 | Fruit Ninja 1.0 | 2.0* | 1 / unset | OpenFeint prompt is **180° upside down** throughout. Return left expands the background while artwork stays offset right and buttons disappear. | Portrait-shaped capture containing a sideways OpenFeint prompt; neither landscape command produces a landscape-shaped capture. | No clean landscape result. SDK 11's portrait/manual-rotation behavior cannot establish physical orientation from these captures alone. Prompt untouched; both SDKs verified in the resumed, normally timed run. [Images](../../tmp/landscape-sdk-20260918/11-com.Halfbrick.Fruit.issue-eval/comparison.jpg) |
| 12 | UNO 1.9.8 | 2.0* | 1 / unset | Tiny sideways sound screen behind upright firmware-warning alert. Survives startup, then **process exits after the first right-rotation command**, before debugger attachment (~41 s). | Survives both rotations. Underlying sound screen is sideways on the initial/returned side and upright on the opposite side; alert remains upright, with large grey regions. | SDK 11 survives this cycle, but layout remains wrong. Legacy SDK configured only; SDK 11 runtime-verified. No crash report captured; unified log shows UIKit assertions with undecodable message bodies, so exit cause is unresolved. Prompts untouched. [Images](../../tmp/landscape-sdk-20260918/12-eval224859/comparison.jpg) |
| 13 | Road Warrior 1.4.2 | 6.1 | 2 / unset | Black throughout startup and rotation captures. PID remains present, but debugger attachment encounters a native `EXC_BREAKPOINT` before SDK verification runs. | Same black captures and failed SDK inspection. | **Not a successful live/menu test.** Both SDKs configured only; native stop observed in Foundation call-stack formatting. No specific root cause established. Right-only orientation declaration. [Images](../../tmp/landscape-sdk-20260918/13-eval330218/comparison.jpg) |
| 14 | Call of Duty Zombies 1.5.0 | 2.0* | 1 / unset | Exits during startup; gone by ~12 s. | Exits during startup; gone by ~10 s. | Neither reaches rotation testing. Both SDKs configured only; no new crash report captured. Return to SpringBoard is evidence of exit, not a game screenshot. [Images](../../tmp/landscape-sdk-20260918/14-com.activision.callofduty/comparison.jpg) |
| 15 | Real Racing 1.27 | 2.0* | 1 / unset | Exits during startup; gone by ~10 s. | Survives and advances through car intro/attract animation. Upright, centered classic-sized viewport across rotation captures; black diagonal bands in some frames. | **SDK 11 improves startup in this pair.** No race/menu interaction tested. Black bands are simulator rendering observations, not proven rotation-induced or device defects. Legacy configured only; SDK 11 verified. [Images](../../tmp/landscape-sdk-20260918/15-com.firemint.realracing/comparison.jpg) |
| 16 | Asphalt 5 1.1.0 | 2.0* | 1 / unset | Black in all captures; process still present and SDK query succeeds. | Same black output through both rotations; SDK query succeeds. | No visible SDK-dependent improvement within ~45 s of capture time. Orientation cannot be judged without rendered content. Both SDKs verified; simulator-only black-screen observation. [Images](../../tmp/landscape-sdk-20260918/16-com.gameloft.Asphalt5/comparison.jpg) |
| 17 | JellyCar 1.5.4 | 2.0* | 1 / unset | Black throughout, process present; initial sideways status-bar text disappears after rotation. | Same behavior. | Both SDKs verified, but no visible content to assess orientation. Right-only declaration. No observed startup improvement within the test window. [Images](../../tmp/landscape-sdk-20260918/17-com.walaber.jellycar/comparison.jpg) |
| 18 | SPY Mouse 1.1.1 | 2.0* | 1 / unset | Exits during startup; gone by ~18 s. | Animated intro advances, but visible content occupies a narrow vertical region; rotation shifts/clips it and displaces the Origin icon. | **SDK 11 improves startup**, but viewport is still broken. No gameplay reached; legacy configured only, SDK 11 verified. [Images](../../tmp/landscape-sdk-20260918/18-com.ea.spymouse.inc/comparison.jpg) |
| 19 | Fruit Ninja HD Free 1.8.0 | 2.0* | 1 / unset | Exits during startup; gone by ~13 s. | Same; gone by ~13 s. | Neither reaches rotation testing; both SDKs configured only. Multi-orientation title included for its landscape support. [Images](../../tmp/landscape-sdk-20260918/19-f/comparison.jpg) |
| 20 | Plants vs. Zombies 1.9.5 (iPhone) | 2.0* | 1 / unset | Upright “Tap to Start” screen. Opposite rotation shrinks it; return shifts it to upper-right. | Reaches the same title screen, initially upright; **return left makes it 180° upside down**, enlarged and clipped. | **SDK 11 introduces a captured inversion** in this pair. Both have viewport instability; neither is a full pass. Both SDKs verified; no start tap. [Images](../../tmp/landscape-sdk-20260918/20-com.popcap.PvZ/comparison.jpg) |
| 21 | Plants vs. Zombies iPad Chinese 1.9.11 | 6.0 | 1 / unset | Exits during startup; gone by ~13 s. | Reaches title screen, but **180° upside down** in initial/opposite captures. Return left makes artwork upright but narrow, severely clipped, and displaced down/right. | SDK 11 improves startup survival, not orientation/layout. iPad-targeted game tested on the same iPhone simulator; not an iPad-device certification. Legacy configured only; SDK 11 verified. [Images](../../tmp/landscape-sdk-20260918/21-com.popcap.ios.chs.PvZiPad/comparison.jpg) |
| 22 | Snoopy’s Street Fair 1.28.0 | 7.0 | 2 / unset | Exits before startup capture; gone by ~33 s. | Exits before startup capture; gone by ~30 s. | No rotation assessment; both SDKs configured only. Small timing difference is not treated as a regression. [Images](../../tmp/landscape-sdk-20260918/22-com.capcom.snoopy.issue-eval/comparison.jpg) |
| 23 | Bubble Ball 1.0 | 2.0* | 1 / unset | Exits during startup; gone by ~10 s. | Same; gone by ~10 s. | No rotation assessment; both SDKs configured only. This comparison does not re-diagnose the prior simulator OpenAL blocker. [Images](../../tmp/landscape-sdk-20260918/23-com.naygames.bubbleball.issue-eval/comparison.jpg) |
| 24 | Fragger DS 1.9.1 | 2.0* | 1 / unset | Exits during startup; gone by ~12 s. | Same; gone by ~12 s. | No rotation assessment; both SDKs configured only. [Images](../../tmp/landscape-sdk-20260918/24-eval157561/comparison.jpg) |
| 25 | Real Racing 3 1.0.2 | 6.0 | 2 / unset | Exits during startup; gone by ~15 s. | Same; gone by ~15 s. | No rotation assessment; both SDKs configured only. Unlike the older Real Racing build, no SDK 11 startup improvement is observed. [Images](../../tmp/landscape-sdk-20260918/25-eval20849/comparison.jpg) |
| 26 | Plants vs. Zombies 2 3.2 / build 3.2.1 | 8.0 | 4 / unset | Upright loading screen at ~37 s; exits after the first right-rotation command, gone by ~42 s. | Same sequence: upright loader, then exit after the first right-rotation command (~42 s). | Rotation-associated exit in both; **causation not isolated** from ongoing loading. Both exit before SDK inspection, so SDKs configured only. [Images](../../tmp/landscape-sdk-20260918/26-eval267926/comparison.jpg) |
| 27 | World of Goo 1.3 | 2.0* | 1 / unset | Exits during startup; gone by ~13 s. | Same; gone by ~13 s. | No rotation assessment; both SDKs configured only. A delayed report for PID 45623 from the previous evening was rejected as unrelated to these runs. [Images](../../tmp/landscape-sdk-20260918/27-eval30269/comparison.jpg) |
| 28 | Death Rally 1.2 | 2.0* | 1 / unset | Exits during startup; gone by ~11 s. | Same; gone by ~11 s. | No rotation assessment; both SDKs configured only. [Images](../../tmp/landscape-sdk-20260918/28-eval3341/comparison.jpg) |

## Longer Ninjago confirmation

Repeated both SDK modes with a 65-second startup wait (actual first captures
at 65–66 s), then the same right/left rotation cycle. Both menus were loaded
before the first rotation. Both SDK values were verified after the captures.

- Legacy reproduces the tall/cropped startup view and sideways, heavily clipped
  menu after rotation. More loading time does not resolve it.
- SDK 11 keeps the full menu upright in all three captures. The viewport still
  shrinks on the opposite side and expands to a wider image on returning left.
- The result confirms an orientation/clipping improvement, not a full layout
  fix or a gameplay pass. Total run times were 80 and 78 seconds respectively.
- [Six-image comparison](../../tmp/landscape-sdk-20260918/02-com.lego.ninjago.thefinalbattle.loaded-menu-repeat/comparison.jpg).

## Final verification and cleanup

- All 28 main result records contain both completed runs. The report has 28
  numbered game rows and links to each comparison image.
- [Final audit](../../tmp/landscape-sdk-20260918/audit.json): no missing results,
  failed rotation commands, missing captures, or settings-restoration errors.
  The 24 unverified main-run SDKs are explicitly recorded as limitations:
  22 exited processes plus the two Road Warrior native stops.
- Re-read every game's current `classicMode`, `spoofSDKVersion`,
  `LCOrientationLock`, and `LCClassicModeCache`: all match the immutable
  pre-test inventory, including the presence/absence of keys. The Ninjago
  repeat also restored its settings. Existing save data was not rolled back.
- Stopped the guest, requested portrait through idb, and stopped only this
  evaluation's isolated companion. No macOS mouse/keyboard or touch input was
  used. Other device/simulator companions were left alone.
- Launcher SHA-256 remains unchanged from the value recorded above. No runtime
  fixes or builds were made for this comparison. Existing source changes were
  left untouched; no commit or push was made.

## Evidence and exclusions

Full-resolution screenshots, raw per-mode results, SDK verification logs,
candidate crash reports, immutable inventory, and settings backups are saved in
[`tmp/landscape-sdk-20260918`](../../tmp/landscape-sdk-20260918/). This local evidence
directory is git-ignored; the Markdown summary is in `docs/compatibility/`.
Crash-report candidates are checked against process IDs and internal capture
times, not filesystem modification time alone. The delayed, unrelated World
of Goo candidate is retained with `matched=false`, not attributed to this run.

The queue includes landscape-only and known landscape-capable games. Jetpack
Joyride and Fruit Ninja HD Free declare portrait support too. Fruit Ninja and
Fragger have incomplete orientation metadata but are included as known
landscape games. Portrait-only games, Chuzzle, utilities, and test fixtures are
excluded. Tomb Raider I and the separate Minecraft 0.6.0 copy were classified
as native ARM64 by LC, so are excluded from this ARM32 SDK comparison. No app
bundle is thinned, replaced, or downloaded for this pass.
