# SDK 11 landscape retest — 19 September 2026

Retested the same 13 games examined in the [Legacy SDK fix pass](legacy-landscape-fixes-2026-09-19.md), plus post-intro checks for Real Racing and SPY Mouse.

## Summary

**SDK 11 still has orientation/layout issues and is not a universal workaround.** Plants vs. Zombies inverts on return rotation; Mini Car Champion and Angry Birds 1.2.0 are sideways/clipped; Fruit Ninja remains portrait-shaped with sideways content; UNO survives but has mismatched alert/game orientation. Several otherwise upright games resize or shift their viewport. Doodle Truck is stable in this limited test.

**Skipping intros matters:** Real Racing reaches an upright, stable garage menu. SPY Mouse's narrow video region disappears after skipping, and its title screen stays upright, but return rotation still enlarges/stretches that screen and moves the Origin overlay. Neither result certifies gameplay.

15 games, 49 recorded comparison captures, all effective SDKs verified, all saved settings restored. No production code changes in this pass.

## Method

- iPhone 17 Pro Max simulator, iOS 27.0; same LiveContainer and installed app bundles/data.
- Effective SDK **11.0** (`0x000b0000`) with **Classic Mode enabled**. Existing Classic Mode cache and orientation locks retained.
- Same installed shared runtime as the final legacy retest: SHA-256 `41fbb02b0f4b2e22a2483286610d38a583fbfa2a6b76186f5baf195ec18da2b0`. No code edits, rebuild, or runtime replacement in this pass.
- Launch using each guest's LiveContainer URL. Capture cold landscape-left, idb landscape-right, then returned-left if the process survives. No Mac keyboard/mouse or gameplay touch tests. In the separate intro follow-ups, use simulator-only idb taps to skip intro videos as requested; leave login, consent, and purchase prompts untouched.
- Wait 60 seconds before the first capture for Ninjago and Jetpack, 30 seconds for the other games. Capture before the final bounded SDK debugger check.
- Restore each game's saved SDK and Classic Mode setting afterward; audit those plus orientation lock and Classic Mode cache.
- Native legacy rotation hooks are gated to SDKs below 8. The preceding native regression matrix passed its SDK 11 cases; this pass checks actual games, including the separate SDK 11 compatibility path.

This is simulator evidence, not physical-device or gameplay certification. Slow loading and rendering artifacts are recorded as simulator observations. The [earlier 28-game comparison](landscape-sdk-comparison-2026-09-18.md) covers additional startup failures but used the earlier runtime. Real Racing and SPY Mouse are being followed beyond their earlier intro-only captures; an intro image alone is not evidence that the menu is laid out correctly.

## Results

| Game | SDK 11 observation | Compared with latest Legacy SDK retest |
| --- | --- | --- |
| Minecraft PE 0.6.1 | Upright in all three captures. No white strip. Opposite rotation shrinks the centered viewport; return shifts it down-left. | Cleaner initial viewport than Legacy, but **viewport stability still fails**. [Captures](../../tmp/sdk11-retest-20260919/01-main/sheet.jpg) |
| LEGO Ninjago, build 5 | Loaded menu stays upright with the play button visible. Centered viewport shrinks on the opposite side, then expands to the display edges on return. | Same remaining size/aspect instability; no sideways/tall menu in this run. [Captures](../../tmp/sdk11-retest-20260919/02-main/sheet.jpg) |
| Angry Birds Rio 1.6.1 | Upright main menu throughout. Opposite-side viewport shrinks; return expands the background while the logo and central play button remain small. | Layout still unstable; logo is more readable than the cropped Legacy capture. [Captures](../../tmp/sdk11-retest-20260919/03-main/sheet.jpg) |
| Doodle Truck 1.7.8 | **No visible orientation/clipping issue:** complete, upright, consistently sized menu across all captures. | Same good control result as Legacy. No gameplay tested. [Captures](../../tmp/sdk11-retest-20260919/04-main/sheet.jpg) |
| OvenBreak 2 1.32 | Still “Heating oven”; upright. Cold viewport is large/centered, shrinks on the opposite side, then shifts down-left. | Loading not resolved within this window; SDK 11 also has viewport drift. [Captures](../../tmp/sdk11-retest-20260919/05-main/sheet.jpg) |
| Jetpack Joyride 1.4.1 | OpenFeint prompt remains upright in all captures. Return expands its background to the full display, leaves artwork at upper-left, and separates the bottom buttons. | Avoids Legacy's opposite-side inversion, **but return layout still fails**. Opt-in prompt untouched. [Captures](../../tmp/sdk11-retest-20260919/06-main/sheet.jpg) |
| Mini Car Champion 1.0 | **Sideways and clipped:** car/menu scene occupies a small square region in every capture, with only part of the artwork and controls visible. | Worse than the latest upright Legacy capture. This run shows a quarter-turn, not the half-turn described in the earlier comparison. [Captures](../../tmp/sdk11-retest-20260919/07-main/sheet.jpg) |
| Blaster Tank 1.5.4 | Upright Game Center connection-error prompt. Viewport shrinks after the first turn and stays small on return. | No inversion; viewport size still changes. Prompt left untouched, gameplay not assessed. [Captures](../../tmp/sdk11-retest-20260919/08-main/sheet.jpg) |
| Angry Birds Lite 1.4.2 | Reaches an upright menu with an unfinished-beta notice. Viewport shrinks on the opposite side and enlarges on return. | Better visible progress than the Legacy sideways splash, but viewport instability remains. Notice untouched; loading-time differences alone do not establish a fix. [Captures](../../tmp/sdk11-retest-20260919/09-main/sheet.jpg) |
| Angry Birds 1.2.0 | **Crystal prompt is sideways and clipped in all three captures.** | SDK 11 changes Legacy's 180° inversion into a 90° error; it does not correct the prompt. Opt-in untouched. [Captures](../../tmp/sdk11-retest-20260919/10-main/sheet.jpg) |
| Fruit Ninja 1.0 | **Portrait-shaped output with a sideways OpenFeint prompt**, unchanged by the two landscape commands. | Different failure from Legacy's inverted landscape prompt; SDK 11 is not a correction. Opt-in untouched. [Captures](../../tmp/sdk11-retest-20260919/11-main/sheet.jpg) |
| UNO 1.9.8 | **Survives both rotations**, but cold/returned-left sound screen is sideways and partly clipped, with a large grey area. Opposite-side sound screen is upright. Firmware-warning alert stays upright throughout. | Better startup/rotation survival than Legacy's exit, but geometry still fails. Alert and sound choice untouched. [Captures](../../tmp/sdk11-retest-20260919/12-main/sheet.jpg) |
| Plants vs. Zombies 1.9.5 | Initially upright, shrinks on the opposite side, then **turns 180° upside down and enlarges/clips on return**. | Worse than the latest Legacy retest, which stayed upright through both turns. [Captures](../../tmp/sdk11-retest-20260919/20-main/sheet.jpg) |

All 13 games survived their three captures and returned effective SDK 11. Intro follow-ups are recorded separately below.

## Intro follow-ups

Both follow-ups use SDK 11 with Classic Mode enabled. Real Racing contains in-engine intro cutscene assets; SPY Mouse has `res/video/intro.mp4`. Skipping is a separate follow-up, not a claim that the initial captures showed their menus.

### Real Racing 1.27

**Intro skipped successfully; garage menu stays upright and centered through both turns.** Career, Quick Race, Time Trial, Profile, Connected, Options, Achievements, Credits, and News remain readable. No menu orientation or viewport-size regression is visible in the three post-transition captures. Black triangular holes/bands remain in the 3D scene, including before rotation; treat these as simulator rendering observations, not proof of a device or rotation bug. No race entered.

- Waited 20 seconds before the cold intro capture. AX exposed only the app, without a skip button.
- The idb screenshot reports a 1320×2868 raw framebuffer at scale 3, i.e. a 440×956-point HID coordinate space. This differs from simctl's orientation-aware landscape screenshot and the guest's 480×320 AX frame.
- One idb HID tap at `(220, 478)` at `00:58:11 UTC` skipped the intro. The four-second capture shows the garage transition; the next capture shows the fully labelled menu, before rotating right/left.
- Effective SDK 11 verified after the captures; saved settings restored. [Captures](../../tmp/sdk11-retest-20260919/15-intro/sheet.jpg), [run/action log](../../tmp/sdk11-retest-20260919/15-intro/result.json).

### SPY Mouse 1.1.1

**Intro skipped successfully; the title is upright and complete, but return-rotation geometry is still unstable.** The narrow, clipped video region is not representative of the post-intro title. Immediately after skipping, the title fills the centered classic viewport; the opposite-side capture is also upright. The Origin icon moves from upper-left to lower-right. Returning left enlarges/stretches the title to the whole landscape display and moves the icon back to upper-left. The logo and “touch to continue” text remain visible. No continue tap or gameplay test was performed.

- The 20-second cold capture still showed the EA logo. A later capture confirmed the animated blue intro before any input was sent.
- One idb HID tap at `(180, 558)` at `01:00:10 UTC` targeted the visible video, away from Origin, using the same raw-framebuffer coordinate mapping as Real Racing. The four-second capture shows the title instead of the video.
- Effective SDK 11 verified after both title rotations; saved settings restored. [Captures](../../tmp/sdk11-retest-20260919/18-intro/sheet.jpg), [run/action log](../../tmp/sdk11-retest-20260919/18-intro/result.json).

## Verification and cleanup

- **15/15 effective SDK readbacks were `0x000b0000`; 49 recorded comparison captures.** Two additional raw idb screenshots were used only to identify intro-input coordinates, not to judge orientation.
- All games remained alive for their captured sequence. No matched crash reports were collected. This is bounded observation, not a claim of crash-free gameplay.
- **15/15 saved configurations restored, zero audit errors:** `classicMode`, `spoofSDKVersion`, `LCOrientationLock`, and `LCClassicModeCache` compared against each game's pre-test values, including absent keys. [Audit](../../tmp/sdk11-retest-20260919/audit.json).
- Shared runtime and launcher hashes are unchanged from the preceding Legacy test. Shared: `41fbb02b0f4b2e22a2483286610d38a583fbfa2a6b76186f5baf195ec18da2b0`; launcher: `e20fbe276ed84ccb51eb0873c0bb2a4c61ee9ea0d02ddd9c6ce199d9e5a9249d`.
- Only this report and ignored diagnostic helpers/evidence were added. Existing source edits were preserved; no fixes, rebuilds, commits, or pushes in this pass.
- LC is stopped, simulator returned to portrait, and this run's isolated idb companion stopped. Pre-existing companions were left alone. Final settings audit and `git diff --check` passed.
- Local evidence is under [sdk11-retest-20260919](../../tmp/sdk11-retest-20260919/). Simulator-only idb rotations/taps and URL launches were used; no Mac keyboard/mouse input. All comparison images use simctl's orientation-aware output without rotating or cropping them for presentation.

Simulator rotations exercise the scene/compositor path; they are not a physical accelerometer/device test. Existing locks and Classic Mode cache were retained. Slow loading and 3D rendering artifacts remain simulator observations. The SDK 11 results do not show that the new pre-iOS-8-only rotation hooks caused these issues; those hooks are disabled in this configuration.

Minecraft's effective SDK was successfully read as `0x000b0000`. A subsequent optional LLDB geometry expression failed to compile because of conflicting `CGRect` debug types; this was a debugger limitation, not a game exit. Its three screenshots were already captured. Remaining runs use the smaller SDK-only inspection to avoid that ambiguity.
