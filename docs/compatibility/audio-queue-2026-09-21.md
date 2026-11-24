# AudioQueue missing APIs — September 21, 2026

## Reported failure

[Issue #52](https://github.com/LiveContainer/LiveExec32/issues/52) reports
SpongeBob Marbles 2.5 (`com.mtvn.SpongeBobMarblesSlides`) crashing when menu music
loops or when Start is selected. Its attached crash report identifies the
missing `_AudioQueueReset` symbol, called by `SoundQueue::play` on the game's
sound thread.

This change addresses that missing symbol and audits the neighboring public
AudioQueue C API against the iOS 10.3 SDK. It does not claim an end-to-end
SpongeBob gameplay retest or complete AudioToolbox coverage.

## Implemented

New guest exports, forwarded to the native queue through the existing token
and lifecycle bridge:

- `AudioQueueReset`
- `AudioQueueGetParameter`
- `AudioQueueGetPropertySize`
- `AudioQueueDeviceTranslateTime`
- `AudioQueueDeviceGetNearestStartTime`

Previously stubbed/partial functions now forwarded to native AudioToolbox:

- `AudioQueueFlush` (previously reported success without flushing)
- `AudioQueueEnqueueBufferWithParameters` (trimming, parameter events, optional
  start time and actual-start timestamp)
- `AudioQueueSetOfflineRenderFormat`
- `AudioQueueOfflineRender` (copies rendered audio and buffer sizes back to the
  ARM32 buffer without exposing native pointers)

New opcodes are appended, preserving existing numbering. The parameter-event,
timestamp and channel-layout ABI is checked explicitly; variable-length input
is bounded. Property-size queries use the same pointer-free property allowlist
as the existing get/set bridge.

Reset uses the ordinary buffer-return callback bridge, including native
`EnqueueDuringReset` errors. Reset requested inside a guest callback follows
the existing deferred Stop/Dispose pattern: the native call waits until the
current callback unwinds, preventing a self-wait when that guest callback runs
on the serialized guest executor. No game-specific hooks were added.

## Verification

Built both frameworks with `LC32_UIKIT_COMPATIBILITY=1` for the host, then ran
ARM32 executables through an isolated command-line runtime in the booted
iOS 27 simulator. No Mac keyboard or mouse input was used. Native macOS
AudioToolbox runs provide reference behavior for the new test cases.

Both framework builds succeeded. Final simulator results: **59/59** queue-control
checks with run-loop callbacks, **59/59** with worker callbacks, **30/30** offline
checks, and **27/27** existing output checks. All four guests exited with code
0. The stream regression also exited 0 with no failures. All three new native
reference runs reported zero failures. `git diff --check` passed.

- `audio_queue_control.c`: normal run-loop and native-worker callback modes;
  repeated reset/reuse, callback-triggered reset, native rejection of enqueue
  during reset, real flush, volume values, property sizes, timestamp translation
  (including in-place output), output canaries and stale queue tokens.
- `audio_queue_offline.c`: trimmed PCM rendering, byte/size copyback, global
  volume, parameterized enqueue, nullable options, aliased timestamp output,
  channel layout, forged-buffer rejection, cleanup and native error parity.
- Existing `audio_queue_output.c`: playback callbacks and re-enqueue are
  required, along with running-property notifications and disposal.
- Existing `audio_file_stream.c`: WAV/AAC parsing and callback regressions
  protect the user-confirmed Asphalt sound-loading fix.
- All nine affected symbols are defined in the built ARM32 framework;
  the complete pre-dispatch/pre-processing-tap AudioQueue C entry-point set
  (29 functions) is exported.

Native reference limitations are intentionally preserved: in the offline test,
the buffer volume event does not override the global volume, and native input
buffers can remain owned by the offline queue until disposal. The bridge does
not fabricate successful buffer release or different PCM output. WAV format
list queries in the stream regression are unsupported by the native parser;
AAC exercises format-list conversion.

Local build/test evidence: `tmp/audio-queue-20260921/` (ignored). The isolated
runtime does not replace other games' selected emulator or alter their data.

## Still outside this patch

The SDK audit still finds these six advanced AudioQueue entry points absent:

- `AudioQueueNewInputWithDispatchQueue`
- `AudioQueueNewOutputWithDispatchQueue`
- `AudioQueueProcessingTapNew`
- `AudioQueueProcessingTapDispose`
- `AudioQueueProcessingTapGetSourceAudio`
- `AudioQueueProcessingTapGetQueueTime`

Those need their own dispatch-block / processing-tap callback and lifetime
bridges. They have not been replaced with fake success stubs. Object-valued or
unknown queue properties also retain the existing unsupported-property result.

The original Asphalt LLDB session was detached and closed; stale LLDB PID
85007 was closed with the user's explicit approval. Xcode and the user's shell
debugger were left alone.

## SpongeBob 2.5 gameplay retest — November 18, 2026

Tested the exact 2.5 release of SpongeBob Marbles & Slides
(`com.mtvn.SpongeBobMarblesSlides`) from
[LegacyStore](https://legacystore.app/app/394392302), copy 206300. The IPA checksum
matched the catalog and its ZIP integrity check passed. This is an iPhone-only
ARM32 build with original SDK 7.1. LiveContainer created `LCAppInfo.plist`
automatically, but initially selected SDK 2.0; the test configuration was
corrected to SDK 7.1 with Classic Mode enabled before testing the current runtime.

Environment: iPhone 17 Pro Max simulator, iOS 27, shared runtime with the
`b2fe48d` rotation-matrix fix. Shared framework SHA-256:
`5846e20cbeccd9bacd6b17008e9e5cdc3cfc9fe56a5f6b5a059e1e506ee8f545`.
Guest QuartzCore SHA-256:
`ac354b80bba084147615541a5e8a24ec48f3227f7d6d60900530ae84ba2d8500`.

- Cold launch, Start, pack selection, level selection, tutorial dialogue,
  drawing, and marble physics worked. Level 1 completed with all six marbles,
  four patties, and a score of 10,815; Next entered Level 2, “Tilt Me!”.
- Two background/resume cycles (Level 1 results and Level 2 tutorial) retained
  the same process and game state. Input worked after dismissing the overlay
  described below. No crash, upside-down presentation, or stretching was
  observed. The old Start/`AudioQueueReset` failure did not recur in this run.
- Native window/root geometry retained a 320 × 568 portrait canvas. After
  resume, the window used a uniform 1.375 scale rather than stretching either
  axis. A raw-pixel comparison of the results table before/after resume was
  effectively unchanged, apart from negligible pixel differences.

At this stage, a blank dimming overlay with an X appeared on cold launch and
both resumes. Closing it restored normal game input. LLDB identified the close
button's target as `PHPublisherContentRequest`, action `dismissFromButton`.
The native hierarchy contained a half-opacity black view and close button,
with no web-view child. This locates the overlay's owner, but does not establish
whether its missing content is caused by the runtime or an obsolete service.
No workaround was added.

Scope limits: Level 2's accelerometer gameplay, later levels, audible sound
quality, physical devices, and iPad were not tested. Elapsed gameplay alone is
not proof that every music-loop path was exercised. All interaction used idb;
LLDB was detached and the test app stopped afterward.

Local evidence: `/private/tmp/lc32-spongebob-20261118.3hrwKH/`, including
`level1-result.png`, `resume1-overlay-closed.png`, `resume2-input.png`,
`launch-state.log`, `resume-overlay-hierarchy.log`, and `overlay-owner.log`.

### Blank overlay investigation and fix — November 18, 2026

The persistent overlay was caused by a shared-runtime workqueue accounting
bug, not by its view layout. PlayHaven showed its loading overlay before
preparing the request on a global dispatch queue. The stuck content request
had no URL, no signed parameters, and no content views. A guest trace showed
the first request's background/main completion chain running, but later
requests never entering their background blocks.

The global queue still contained continuations, with no remaining worker;
its `dgq_pending` counter was `0xffffffff` (-1). The runtime's blocked-worker
compensation could invent an ordinary worker without a corresponding
libdispatch request. Each worker entry decrements the pending counter, and
future enqueues request workers only when that counter is zero. This matches
[Apple's libdispatch worker-entry and queue-wakeup accounting](https://github.com/apple-oss-distributions/libdispatch/blob/libdispatch-703.50.37/src/queue.c).
Manually draining the main queue did not resolve the stranded global work.

Removed the unrequested-worker fallback and its unused tracking fields.
Blocking boundaries still service genuine outstanding worker requests and
ready events. Existing worker limits and event-manager serialization remain
unchanged. There is no PlayHaven hook, game-name check, ad suppression, queue
memory patch, or UIKit workaround in the fix.

Verification:

- Expanded `test/dispatch_main_queue.m` with a blocking pipe `poll`, concurrent
  work while that worker is blocked, and three subsequent batches of global
  queue work returning to main. Before: **36 checks, 5 failures**. Fixed:
  **36/36 pass**, repeated three times. Native macOS reference: **36/36 pass**.
- Existing dispatch timer regression: **38/38 pass**, including progress with
  four waiting workers. Native pthread smoke test: **72,000 increments, pass**.
- SpongeBob's menu and Level 2 tutorial both survived background/resume in
  the same process, with no X tap needed. Menu navigation and tutorial input
  worked. The settled native hierarchy contained only the game's EAGLView;
  the global queue was empty and its pending counter was zero.
- These are simulator results with original SDK 7.1 and Classic Mode. They
  establish that the persistent loading overlay clears normally, not that
  the legacy advertising service now supplies usable ads.

Follow-up startup logs show PlayHaven requests reaching their failure handlers
with “A server with the specified hostname could not be found.” The SDK's
ordinary error handling now removes the overlay; the runtime does not hide it.
Three additional direct-launch smoke runs stayed alive and logged those
handled failures. Direct launches do not reliably apply Classic Mode, so those
runs are not layout-validation evidence.

One separate debugger-free URL-launch repeat did crash during startup with a
native `-[__NSDictionaryM setObject:forKey:]` exception reached through a guest
notification callback. Its cause remains unresolved; it was not reproduced
in the three subsequent direct-launch smoke runs. Preserve
`/Users/duy/Library/Logs/DiagnosticReports/LiveContainer-2026-11-18-073056.ips`
for follow-up. This result is not counted as a successful cold launch, and no
blanket nil-dictionary suppression was added. A final debugger-free URL launch
and same-process resume also reached the correctly sized menu with no stuck
overlay (`fixed-final-url-launch.png`, `fixed-final-url-resume.png`).

Fixed simulator shared-framework SHA-256:
`007b6d857132d020d7b3534109f40b967256faca10c2059924ecc90a5b859096`.
Additional evidence in the same local directory: `trace-request.log`,
`queue-memory2.log`, `dispatch-final-before.log`, `dispatch-fixed.log`,
`native-dispatch-test.log`, `timers-fixed.log`, `pthreads-fixed.log`,
`fixed-menu-resume.png`, `fixed-level2-resume.png`, and `fixed-state.log`.
Debugger-induced failed runs were discarded as gameplay evidence; final
launch/resume verification used normal launches, with diagnostic debuggers
detached afterward.

### Intermittent startup exception follow-up — November 18, 2026

**Guest-address reuse race reproduced and fixed; the original game exception
has not been caught again.** LiveContainer's
saved exception text identifies the missing value from the `073056.ips` crash:
`object cannot be nil (key: DaysSinceLastUse)`. The saved stack addresses match
that report. The exception text is preserved locally as
`/private/tmp/lc32-spongebob-20261118.3hrwKH/saved-startup-exception.txt`.

Inspection of the actual ARMv7s slice initially suggested ADMS analytics:
`setNotInstallVariables` obtains the last-use date (`OMCK5`), calls
`daysSince:to:` (date interval / 86400, `floor`, `stringWithFormat:@"%1.0f"`),
then passes the string to `setContextDataValue:forKey:`. That setter checks
the value's and key's `length` before inserting into the native dictionary.
However, this setter's key is **`a.DaysSinceLastUse`**, not the bare key in
the exception. `translateContextData:withFilter:` subsequently splits dotted
keys and inserts guest-defined `ADMS_ContextData` nodes into native
dictionaries. At that point `DaysSinceLastUse` identifies a **node**, not the
formatted string. The original string-lifetime hypothesis was too narrow.

Initial checks, before the new mapping fix:

- Three debugger-monitored direct launches and six debugger-monitored normal
  URL launches did not hit `objc_exception_throw` during their observation
  windows. Five additional direct console launches also stayed alive.
- A temporary invalid-dictionary-insertion stop probe did not trigger during
  20 normal URL cold-start attempts. Each process was still alive at the
  25-second check; these are startup smoke checks, not 20 gameplay passes.
  A subsequent background/resume followed by another cold launch reached
  the menu (`startup-after-resume.png`). Shorter preliminary runs that could
  end before analytics initialization are not counted in those 20 attempts.
- Added `test/string_format_lifetime.m` (`make -C test string-format-lifetime`)
  to exercise the date/format/dictionary path inside notification callbacks
  on five threads, draining both guest and native autorelease pools. All
  10,000 iterations passed on the simulator and in a native macOS reference
  run. This is stress coverage, **not a reproducer for the startup crash**.

Replaying the game's `setNotInstallVariables` 500 times and its actual
`translateContextData:withFilter:` method 2,000 times in LLDB did not throw.
Neither replay is a cold-start reproduction.

#### Reproduced mapping race

Added `test/context_data_lifetime.m` (`gmake -C test context-data-lifetime`).
It models the ADMS tree with guest-defined, autoreleased nodes and native
dictionaries, invoked through native notification callbacks on five threads.
It checks identity and retained values across pool drains, then verifies that
all nodes deallocate. Native macOS passed 25,000 node lifetimes; the simulator's
single-thread control passed 5,000. Concurrent simulator runs failed with an
unexpected nil dictionary, including at iterations 9 and 120.

A temporary dead-mapping stop probe captured the cause in LLDB:

- Guest address `0x1014eef0` was being initialized as a fresh dictionary proxy.
- Its registry entry still described an older `LC32ContextNode` mirror at
  `0x100a30590`, generation 911, with retirement provenance
  `GuestMirrorWithTransferredReference` on another thread.
- That other thread had already completed guest deallocation and was still
  unwinding `LC32RetireGuestMirrorWithTransferredReference`.

Guest root deallocation already detached keys for `NativePeerDeallocating`,
but omitted the coordinated guest-mirror retirement path. The allocator could
therefore reuse a freed ARM32 address while lookup still returned the old
retiring peer or the dead-mapping sentinel. This explains how a valid newly
allocated object can turn into a nil native argument; it is consistent with
the game's exception, but the original game run was not directly captured.

`LC32DetachRetiringGuestKey` now detaches both pin-driven retirement cases
before the guest allocation is freed. The old native-address tombstone stays
in the existing generation-indexed retirement storage until finalization;
cleanup cannot remove a newer mapping that reuses the guest address. No
nil-dictionary suppression, analytics disabling, game-specific checks, or
permanent diagnostic stop probes were added.

#### Separate string initializer fix

All four manual `initWithFormat:` variants assigned `host_self` directly,
bypassing the canonical reverse mapping and lifetime pin. The new test found
four identity failures when storing these strings in a native array and
reading them back; native macOS passed. They now use the existing
`LC32AdoptHostInitializerResult` helper. All four identity checks and all four
container-lifetime checks pass. This is an independently verified defect,
not a claim that SpongeBob's `stringWithFormat:` caused the startup crash.

Verification with the fixed shared runtime:

- Five fresh-process concurrent context tests: **125,000 nodes created and
  destroyed, zero failures**.
- Formatting/date stress: **10,000 iterations, zero failures**, plus all eight
  initializer identity/lifetime checks.
- Existing guest-proxy lifetime, native-proxy release, ARC-proxy lifetime,
  and ownership-publication race regressions all exited successfully.
- SpongeBob reached the menu on four consecutive normal URL cold starts,
  observed after 25 seconds each. A separate normal launch and same-process
  background/resume (PID 40335) also reached the menu. These are startup/resume
  smoke checks, not a complete gameplay pass or proof that every intermittent
  startup failure is eliminated.

Local evidence remains in `/private/tmp/lc32-spongebob-20261118.3hrwKH`:
`context-parallel.log`, `context-probe-lldb.log`, `context-fixed*.log`,
`format-init-before.log`, `format-init-after.log`, `context-replay.log`, and
`fixed-{guest-proxy-lifetime,native-proxy-release,arc-proxy-lifetime,ownership-publication-race,string-format-lifetime}.log`.
The final test sources also passed in `final-{context-data,string-format}-lifetime.log`;
game captures are `lifetime-cold-{1,2,3,4}.png` and `lifetime-fixed-resume.png`.

### SpongeBob iPad simulator follow-up — November 18, 2026

Tested Marbles & Slides 2.5 on iPad (A16), iOS 27, simulator
`3FB9DBF4-A92A-469B-B2AB-66589F29AE2D`, original SDK 7.1 and Classic Mode.
The shared simulator runtime includes both lifetime fixes above; its SHA-256
is `8485222fc5cabe278c80348fb93ab17063c028e16e4f2902287e2370ce0eb505`.

The iPad uses separate bundle metadata and a cloned test save. Resources are
symlinked, and the executable is hard-linked, without duplicating the game.
Initially symlinking the executable too caused a test-setup failure: its
resolved path made the guest mount the original bundle while native resource
lookup used the iPad shadow bundle. Atlas loading then passed a null file
handle to `fread`. Changing only the shadow executable to a hard link fixed
startup; no runtime or game-binary change was needed. The iPad recalculated
its own Classic Mode cache (2), rather than inheriting the phone's cache.

After correcting that setup, PID 74505 reached the menu and level 2. Four
same-process background/resume cycles passed: menu, level-introduction panel,
in-level dialogue, and interactive playfield. The centered portrait viewport
kept its dimensions and proportions, without upside-down output, clipping,
blank overlay, or crash. Visible Start, pack/level selection, and dialogue
controls responded after resume. This is a startup/layout/input smoke test;
tilt-based play, level completion, and physical iPadOS remain untested.
A final normal cold launch (PID 76378) also reached the menu at the 25-second
check. The test game was stopped afterward; the iPad installation is retained.

Evidence: `/private/tmp/lc32-spongebob-ipad-20261118.QdzX6l`, including
`hardlink-menu.png`, `menu-resumed.png`, `gameplay-{before,resumed}.png`
(level-introduction panel), `active-level-{before,resumed}.png` (dialogue),
`playfield-{before,resumed}.png`, and `final-cold-menu.png`.

### SpongeBob physical iPhone follow-up — November 18, 2026

Tested Marbles & Slides 2.5 on iPhone 15 Pro Max (`iPhone16,2`), iOS 26.1,
using an isolated game, cloned save, and shared-runtime installation. The
original SDK 7.1 override (`459008`) and Classic Mode are enabled; LiveContainer
recalculated its Classic Mode cache as 2. The deployed shared framework SHA-256
is `65ce510474e8067eadd4d4d320e55b9c41c5de13248712ff456b425cbac2d080`,
and guest Foundation is
`ee7c4eb4f5afd5ffbb45b10dcb04f3108dad6623346f8bdccd2a751a0af3065e`.

The first launch exposed a deployment issue: the selected isolated runtime was
still an unpatched main executable, which `dlopen` rejected. Launching that
runtime directly through LiveContainer completed its normal patch/sign flow
(`LCPatchRevision` 7); no runtime source change was needed. Remote screenshot
captures also required correcting the output file's ownership, and some later
fresh captures were black even outside the game. Visual results below use only
the subsequent successful captures, not those black images.

PID 7045 reached the upright menu. Two Settings-to-LiveContainer
background/resume cycles retained that same process and the same portrait
viewport dimensions and proportions, with no visible clipping, blank overlay,
or crash.

After the user entered a level, three additional background/resume cycles
also retained PID 7045. Captures show the active playfield before the first
cycle, a completed-level summary afterward (eight marbles saved), and the next
level's dialogue after the second cycle. User interaction continued between
captures, so these are not identical-scene comparisons. The third cycle
preserved that next-level dialogue and playfield, allowing a direct comparison:
the portrait viewport and artwork kept their dimensions and proportions, with
no blank overlay, clipping, or upside-down output. Level completion and
progression were observed; tilt accuracy and extended gameplay were not
independently evaluated.

All five resume cycles completed without a process restart or observed crash.
No debugger remained attached. The isolated test copy remains running for the
user; the original game and runtime were preserved. This smoke test does not
rule out every intermittent startup failure.

Evidence: `/private/tmp/lc32-spongebob-iphone15-20261118.m3vHvd`, including
`menu-retry.png`, `menu-resume-1.png`, `menu-resume-2.png`,
`level-before-resume.png`, `level-resume-1.png` (completion summary),
`completion-resume-2.png` (next-level dialogue), and `level-resume-3.png`.
