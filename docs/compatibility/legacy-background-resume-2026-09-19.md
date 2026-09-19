# Legacy SDK background/resume evaluation — 19 September 2026

Completed the evaluation of all **45 installed game/version bundles**, prioritizing OvenBreak 2 and original Legacy SDKs. **OvenBreak's reproduced background-task timeout is fixed and retested.** SDK 11 was not tested in this pass.

Of the **43 ARM32 bundles**: 24 survived at the observed menu, prompt, or loading screen; two additional bundles kept the same active PID but remained black; 15 failed during startup; one declares exit-on-suspend and exited on Home; and Temple Run 2 has an unresolved intermittent foreground exception despite two successful clean retries. The two LC-native-classified controls were blocked before a lifecycle test. This is not a claim that every game is fixed or gameplay-compatible. [Machine-readable result summary](../../tmp/resume-eval-20260919/results-summary.json).

## Method

- iPhone 17 Pro Max, iOS 27.0; existing LC app bundles and data. No new game downloads.
- For ARM32 games, temporarily use the SDK declared by the executable's ARM32 slice; missing/zero SDK retains LC's 2.0 fallback. All 43 had Classic Mode enabled; existing cache and orientation locks are retained. Restore saved settings afterward, including any previous SDK 11 override.
- Launch the guest using its normal LC URL; send simulator-only idb Home; wait in the background; foreground the existing LC process with simctl. Require the same PID, not a fresh launch, to count as surviving resume. Record Home-screen evidence and before/after screenshots.
- Keep startup failures separate from background and foreground failures. Repeat failing transitions with diagnostics and a no-background control when needed. Rendering and loading slowness remain simulator observations.
- No Mac keyboard/mouse or opt-in/purchase interactions. Existing dirty source edits are preserved. No commits or pushes.

## Test setup

The installed launcher had been rebuilt at 09:15 local time as `MH_EXECUTE`. LC's error was `cannot dlopen a main executable`, so the first `05-pilot` attempt never tested OvenBreak and is excluded. The current launcher/shared framework were backed up before preparing an LC-compatible launcher with preserved segment indices and an ad-hoc signature. No launcher source change. The current shared framework is not replaced with the older pass's build.

Pre-test shared-framework SHA-256: `eb41d029ff8fc5bbe210f14bb7a8bea6e624bf46d36f924aef69618f03f58b62`.
Pre-conversion launcher SHA-256: `903df838519af85dca1b1b399122f720b57f278f0fc1268e0403459c08f2d83f`.

## OvenBreak background termination

OvenBreak 2 1.32, SDK 6.1: first ~10-second background interval and return survived with PID 63698. During a second ~30-second background interval, the process disappeared before foregrounding. The game remained at “Heating oven” before and after the first cycle. This is a loading-screen lifecycle reproduction, not a gameplay-resume result.

The system log identifies `OS_REASON_RUNNINGBOARD`, code `0x2182BAD2`: iOS timed out waiting for `Shared Background Assertion 1 for com.devsisters.ovenbreakx` to be invalidated. This termination did not produce an `.ips` crash report (`reportType:None`). The debugger run is diagnostic only: attaching a debugger suppressed the termination and cannot count as a clean pass.

Native tracing confirmed that UIKit invoked both expiration callbacks through LC32's typed guest-block wrapper. Their captured original callbacks are in the game executable at unslid Thumb addresses `0x25d2b8` and `0x25ef24`. Both check Flurry's `logLevel`, optionally call `NSLog`, and return; neither ends its task. The first message is `Flurry: Session suspend expiration handler reached`. This is a task leak in the bundled legacy analytics code, not a dropped expiration callback. Apple's API requires callers to balance their background tasks with `endBackgroundTask:`. [Apple documentation](https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(expirationhandler:))

### Shared compatibility fix

The existing guest `UIApplication+LC32BlockCompatibility` adapter now covers both public begin methods and end. It retains the typed wrapper required by legacy block signatures, invokes the client's expiration handler, then releases the expired task if the client did not already do so. A small mutex-protected set consumes each task registration once; normal completion, handler-owned completion, and late/duplicate end calls cannot double-end the native assertion. This affects guest-created tasks only, with no bundle-name checks, global native UIKit swizzles, or generic bridge hot-path checks.

The shim generator omits all three manually implemented methods. Native tests compile the production guest adapter against a fake host: **17/17 checks passed**, including anonymous/named/nil handlers, reentrant task creation, duplicate/racing completion, and host refusal. ARMv7s UIKit rebuilt successfully; the generator object-output regression also passed.

**Post-fix: OvenBreak survived two 40-second background intervals, with 15 seconds of foreground observation after each, in the same PID 71448.** No debugger was attached until both cycles finished. The final inspection confirmed SDK `0x60100` and active application state. Settings were restored exactly. The game still showed “Heating oven”; its separate loading problem is not fixed. [Captures](../../tmp/resume-eval-20260919/05-fixed/sheet.jpg), [result](../../tmp/resume-eval-20260919/05-fixed/result.json).

Deployed guest UIKit SHA-256: `9f5ea328fbfd119d04232c7479007b42113d3b6b96c7183ca838c649359c91a7`. The native shared framework remains unchanged. Both prior UIKit runtime/resource binaries are backed up in the evidence directory.

Additional host regressions: scalar callback signatures (87 cases), guest timer queue (80 checks), legacy nib loading, and Mach exception-port handling all passed.

### Early sweep observations

Before deploying the fix, Minecraft PE 0.6.1 (SDK 6.0) and LEGO Ninjago (SDK 6.1) survived a 35-second background interval and returned in the same PID. Ninjago's title canvas became smaller after resume; that is a separate layout observation, not a lifecycle-crash pass for gameplay. The first Angry Birds Rio sweep attempt was interrupted for deployment before its startup observation finished and is excluded.

Local evidence: [resume-eval-20260919](../../tmp/resume-eval-20260919/), [OvenBreak initial run](../../tmp/resume-eval-20260919/05-baseline/result.json). Raw logs, captures, settings snapshots, and runtime backups are local ignored artifacts, not files intended for a source commit.

## Post-fix game matrix

“Survived” means the same PID survived the observed lifecycle at the listed screen, not completed gameplay. Except OvenBreak's two 40-second cycles, the sweep uses one 35-second background interval and 10 seconds after return. Cold startup is observed for 30 seconds (60 for slower Ninjago, Jetpack, and The Heist). SDK inspection occurs only afterward, so a debugger cannot suppress a termination during the test.

| Game/version | Original SDK used | Lifecycle result | Screen / remaining observation |
| --- | --- | --- | --- |
| Minecraft PE 0.6.1 | 6.0 | Survived | Main menu unchanged; small left-aligned canvas/white strip remain. |
| LEGO Ninjago build 5 | 6.1 | Survived | Main menu; canvas shrinks on return. |
| Angry Birds Rio 1.6.1 | 6.1 | Survived | Menu/rating prompt; canvas shrinks, logo/prompt clipping remains. No rating interaction. |
| Doodle Truck 1.7.8 | 7.0 | Survived | Main menu; canvas moves toward the lower-left on return. |
| OvenBreak 2 1.32 | 6.1 | Fixed reproduced timeout; survived twice | Still at “Heating oven”; not a gameplay or loading fix. |
| Jetpack Joyride 1.4.1 | 6.0 | Survived | OpenFeint opt-in prompt untouched; expanded background and displaced artwork/buttons after resume. |
| Mini Car Champion 1.0 | 2.0 fallback | Survived on timing-valid retry | Main menu shrinks/moves to upper-left on return. |
| Blaster Tank 1.5.4 | 2.0 fallback | Exits on background; app requests exit-on-suspend | At Game Center connection-error screen. `UIApplicationExitsOnSuspend = true`; immediate exit with no `.ips`, consistent with its declared lifecycle. No same-process resume expected; flag left unchanged. |
| Angry Birds Lite 1.4.2 | 2.0 fallback | Survived | Remained on Angry Birds artwork, not a verified playable menu; smaller after return. Portrait-frame capture. |
| Angry Birds 1.2.0 | 2.0 fallback | Survived | Crystal opt-in prompt untouched; smaller after return. Portrait-frame capture. |
| Fruit Ninja 1.0 | 2.0 fallback | Survived | OpenFeint opt-in prompt untouched; smaller after return. Portrait-frame capture. |
| UNO 1.9.8 | 2.0 fallback | Survived | Startup firmware/notification warning untouched; underlying sound prompt/layout changes on resume. |
| Road Warrior 1.4.2 | 6.1 configured | Startup blocked; PID survival is not a pass | Black throughout. A 90-second foreground-only control reproduces guest SIGABRT in `LC32ForwardingFailure` / `LC32GuestForwardMessageStret`, then a native `NSCallStackArray` trap while formatting the exception. This occurs without backgrounding. The longer lifecycle run kept a PID but never established a functioning game. |
| Call of Duty Zombies 1.5.0 | 2.0 fallback | Startup blocked; resume not tested | Recovered crash-service report: guest SIGSEGV on `MemoryWrite8` at `0x142e6000`, game offset `+0xba0e6`, followed by native SIGABRT about 6 seconds after launch. |
| Real Racing 1.27 | 2.0 fallback | Startup blocked; resume not tested | Recovered report: guest SIGSEGV writing address zero through `_platform_memmove` / `strcpy`, then game code; native SIGABRT about 7 seconds after launch. |
| Asphalt 5 1.1.0 | 2.0 fallback | Same PID survived; black-screen limitation | SDK and active state verified after resume; no diagnostic trap. Black before/after, so no working menu or gameplay established. |
| JellyCar 1.5.4 | 2.0 fallback | Same PID survived; black-screen limitation | SDK and active state verified; no diagnostic trap. No working menu or gameplay established. |
| SPY Mouse 1.1.1 | 2.0 fallback | Startup blocked; resume not tested | Guest SIGSEGV in `CC_PushNotificationManager_Delegate application:didFailToRegisterForRemoteNotificationsWithError:`, followed by native SIGABRT. Intro skip not reachable. |
| Fruit Ninja HD Free 1.8.0 | 2.0 fallback | Startup blocked; resume not tested | Guest SIGSEGV with invalid PC `0x7274732c` / invalid frame pointer, followed by native SIGABRT around 6 seconds after launch. |
| Plants vs. Zombies 1.9.5 | 2.0 fallback | Survived | “Tap to start” title; canvas shrinks/moves to upper-left on return. |
| Plants vs. Zombies iPad Chinese 1.9.11 | 6.0 | Startup blocked; resume not tested | Native `UIWindow _finishedFirstHalfRotation:context:` unrecognized selector while making its initial window visible. |
| Snoopy’s Street Fair 1.28.0 | 7.0 | Startup blocked; resume not tested | Native UIKit assertion / SIGTRAP about 29 seconds after launch, before Home. Crash service confirms BaseBoard `threading violation: expected the main thread`. |
| Bubble Ball 1.0 | 2.0 fallback | Startup blocked; resume not tested | Exited during cold start. Also declares `UIApplicationExitsOnSuspend = true`, but never reached a background test. |
| Fragger DS 1.9.1 | 2.0 fallback | Startup blocked; resume not tested | UIKit assertion / SIGABRT about 7 seconds after launch. |
| Real Racing 3 1.0.2 | 6.0 | Startup blocked; resume not tested | UIKit assertion / SIGTRAP about 9 seconds after launch. |
| Plants vs. Zombies 2 3.2 (build 3.2.1) | 8.0 | Startup blocked; transition result inconclusive | First run exited just after Home while still loading. A 90-second foreground-only control crashed after ~36 seconds without Home: `performSelector target NSThread has no native thread`, from game offsets `+0x48913c` / `+0x46a598`. This reproduces the previously identified startup blocker; no independent resume failure established. |
| World of Goo 1.3 | 2.0 fallback | Startup blocked; resume not tested | Guest SIGSEGV in `IPhoneEAGLView createFramebuffer`, called from `layoutSubviews`, before Home. |
| Death Rally 1.2 | 2.0 fallback | Startup blocked; resume not tested | Native SIGTRAP about 6 seconds after launch, reproduced on the retry. |
| Paper Toss 1.0 | 2.0 fallback | Survived | Difficulty-selection menu; canvas shrinks/moves to upper-left after return. |
| Cut the Rope 2.6 | 8.3 | Survived | Daily-gift overlay left untouched; canvas shrinks/moves upward after return. |
| Where’s My XiYangYang? 1.0 | 7.0 | Survived | Title menu; canvas shrinks/moves upward after return. |
| Flappy Bird 1.2 | 7.0 | Survived | Main menu; canvas shrinks/moves upward after return. |
| Temple Run 1.0 | 2.0 fallback | Survived | Main menu; canvas shrinks/moves upward after return. |
| Temple Run 2 1.0 | 6.0 | Intermittent foreground crash remains unresolved | First run aborted just after return: native `-[NSNull length]` unrecognized selector. A 90-second foreground-only control reached the menu; a diagnostic lifecycle run and two subsequent **no-debugger** cycles survived. No Temple Run-specific fix or blanket `NSNull` workaround added. |
| Tiny Death Star 1.4.2 | 7.1 | Survived | Age-selection screen left untouched; canvas shrinks/moves upward after return. |
| Minecraft PE 0.6.0, native-classified copy | Native control; unchanged | Startup blocked; not an ARM32/Legacy result | LC classifies this executable as native ARM64 (Mach-O SDK 18.2). BaseBoard refuses launch because the UIScene lifecycle is required for its linked SDK. No SDK override or architecture change made. |
| Chuzzle 1.0 | 2.0 fallback | Survived | Game-mode menu; canvas shrinks/moves upward after return. |
| The Heist 1.1.2 | 6.1 | Survived | Vault/puzzle screen; canvas shrinks/moves upward after return. |
| Temple Run 1.1 | 2.0 fallback | Survived | Main menu; canvas shrinks/moves upward after return. |
| Where’s My Water? 1.0.0 | 2.0 fallback | Survived | Main menu; canvas shrinks/moves upward after return. |
| Cut the Rope 1.5 | 2.0 fallback | Survived | Main menu; canvas shrinks/moves upward after return. |
| Doodle Jump 2.4 | 2.0 fallback | Survived | Score-submission opt-in prompt left untouched; canvas shrinks/moves upward after return. |
| Cut the Rope 1.0 | 2.0 fallback | Startup blocked; resume not tested | Guest SIGABRT in `LC32_releaseGuestOwnershipOnly`, called from game offset `+0x756e8`; exited about 5 seconds after launch. The 1.5 and 2.6 copies are separate passing lifecycle results. |
| Spooky Pop 0.2.10 | 8.1 | Startup blocked; resume not tested | Native SIGTRAP about 9 seconds after launch. No useful exception reason recovered from the crash service. |
| Tomb Raider I 1.0.2, native-classified copy | Native control; unchanged | Loader blocked; not an ARM32/Legacy result | LC attempts the ARM64 slice; `dlopen` rejects its code signature (`sliceOffset=0x00318000`). SDK setting and architecture classification left unchanged. |

All installed game/version entries are represented above. Non-game utilities and synthetic LC32 test bundles were excluded. No game downloads, reinstalls, or save-data resets were performed.

The first post-fix Mini Car Champion attempt (`07-retest`) was invalidated by a host scheduling/sleep gap during startup, before backgrounding. Its saved settings were restored and it is excluded from game-failure counts. The rest of the sweep used timing-gap retries and an idle-sleep assertion scoped to the runner; explicit host sleep was still respected.

The first Asphalt 5 attempt (`16-retest`) was interrupted during runner coordination before its startup observation finished; its settings were restored. It is excluded; the completed retry is `16-retest-2`. Road Warrior's diagnostic control is in `13-foreground-control/control-stack.log`; its no-debugger long observation is `13-long-resume`. PvZ2's no-background crash report is saved in `26-foreground-control/result.json` (`lcErrorAfter`).

## Temple Run 2 follow-up and crash-report limits

Temple Run 2's first run (PID 9928) survived backgrounding but aborted shortly after foregrounding. The host crash service recovered `NSInvalidArgumentException`, `-[NSNull length]: unrecognized selector sent to instance`. Its absence from the normal report directory was **not** evidence of a clean exit: OSAnalytics rejected the `.ips` request with `Log limit exceeded`. The system crash-report limit was left unchanged. [Recovered exception](../../tmp/resume-eval-20260919/34-retest/reportcrash-service.log), [report-limit evidence](../../tmp/resume-eval-20260919/34-retest/reportcrash-completion.log).

The 90-second no-background control reached the main menu (PID 12167). The debugger-assisted lifecycle run (PID 13311) did not reproduce the abort and is diagnostic only. A fresh run without a debugger through both cycles (PID 14568) survived two 35-second background / 15-second foreground intervals, progressing from the animated intro to the menu. Final SDK 6.0 and active application state were verified afterward. [Clean repeat captures](../../tmp/resume-eval-20260919/34-clean-repeat/sheet.jpg), [result](../../tmp/resume-eval-20260919/34-clean-repeat/result.json).

This remains an intermittent failure, **not a claimed fix**. The available evidence does not identify the caller that treated `NSNull` as a string, nor establish that backgrounding is necessary to trigger it. A generic `NSNull length` hook would conceal the invalid value without establishing the cause, so none was added.

## Verification and cleanup

- Final audit: **45/45 saved configurations unchanged**, comparing Classic Mode, SDK override (including absence), orientation lock, Classic Mode cache, data-container UUID, and ARM32 classification with the pre-test inventory. [Audit](../../tmp/resume-eval-20260919/settings-audit.json).
- Every ARM32 result classified as surviving has a same-PID check plus post-cycle SDK and active-state verification. The two black-screen cases remain explicitly limited. Diagnostic/debugger runs are not substituted for clean lifecycle tests.
- The production background-task adapter passed **17/17** host checks; scalar callbacks (87 cases), the guest timer queue (80 checks), legacy nib loading, Mach exception ports, and the shim-generator regression passed. The ARMv7s UIKit build succeeded. Final source whitespace check passed.
- Patched UIKit is deployed to the current launcher and resource tree. The native shared-framework hash remains unchanged from the pre-test value. Prior runtime binaries and the pre-existing source diff are backed up in the evidence directory.
- LC was terminated after the final test, simulator orientation restored to portrait, and only this evaluation's isolated idb companion stopped. The runner's idle-sleep assertion ended with its process. No Mac keyboard/mouse input was used.
- Existing dirty changes were preserved. Nothing committed or pushed. Remaining startup failures, Temple Run 2's intermittent exception, and simulator rendering/loading observations are **not fixed by this change**.
