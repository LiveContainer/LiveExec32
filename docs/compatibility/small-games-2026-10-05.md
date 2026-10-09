# Small-game simulator pass — October 5, 2026

Six previously untested copies from Legacy Store, each below 21 MB (88.7 MB
combined). This is a smoke test, not full-game or real-device certification.
The follow-up fixes reproduced crashes one game at a time, with focused ARM32
regression tests and simulator retests. Changes are not yet committed.

## Configuration and installation

- Runtime source: `dev` at `eb728a0`; `gmake -j4` passed.
- iPhone 17 Pro Max / iOS 27.0 simulator
  (`94D177DD-0AEE-41BF-B182-ED4FEAA28100`).
- Legacy SDK, Classic Mode enabled, `LC32_UIKIT_COMPATIBILITY=1`.
  These copies do not supply a usable SDK version in their Mach-O load
  commands, so they use LC's existing SDK 2.0 floor (`131072`). This is not a
  claim that their original build SDK was exactly 2.0.
- Downloaded through the approved Legacy Store catalog/download endpoints.
  Download sizes, catalog SHA-1 values, ZIP integrity, and unencrypted ARM32
  slices were checked. These are integrity checks, not an independent
  authenticity or security audit.
- Installed app bundles as new `small<COPY>.app` symlinks. Existing games and
  saves were not replaced. LC generated all six `LCAppInfo.plist` files.
- First-launch metadata creation was sometimes delayed. The default emulator
  points to a device executable, which cannot be loaded as a simulator dylib;
  a private simulator runtime was therefore selected per game. These setup
  errors are not game failures. No global emulator selection was changed.
- The simulator runtime uses the freshly built shared frameworks and packaged
  RootFS, with an existing simulator-loadable launcher. Guest frameworks were
  taken from the packaged RootFS, not older intermediate armv7s outputs.
- Normal visual tests launch through LC URLs. Direct debugger launches are
  diagnostic only and are not used to assess the Classic Mode viewport.
  All touches use idb; no Mac keyboard, mouse, or focus changes are used.

## Results

Sizes are compressed IPA sizes in decimal MB.

| Game / version | Catalog copy | MB | Observed result |
| --- | --- | ---: | --- |
| [Canabalt 1.7](https://legacystore.app/app/333180061) | 79580 | 14.1 | **Startup crash fixed.** Reaches the title menu and stays running. Clipped/rotated simulator viewport prevents reliable gameplay/replay testing; rendering remains outside this pass. |
| [Tiny Wings 1.1.3](https://legacystore.app/app/417817520) | 30717 | 8.1 | **Reached gameplay.** Main menu, all four tutorial pages, Play, and a one-second touch completed without a crash. No full run completed. |
| [Osmos 1.6.4](https://legacystore.app/app/382991304) | 114235 | 16.8 | **Reached first tutorial scene.** Slow startup initially looked black, then reached Odyssey/Arcade. On a normal relaunch, Odyssey → skip introductory text reached the blue-mote/target scene without a crash. Movement and tutorial completion untested. |
| [Super Hexagon 1.3 / build 1.3.0](https://legacystore.app/app/549027629) | 20790 | 17.8 | **Still crashes; cause identified.** Adobe AIR's lazy initialization relies on guest Mach exception delivery, which is not implemented. No workaround that bypasses the required initialization was added. |
| [EDGE 1.62](https://legacystore.app/app/300896018) | 195043 | 20.2 | **Reached first level.** English → decline optional Game Center → Edge Challenge → New Game. No crash in these transitions; movement and level completion untested. |
| [NinJump 1.60.4](https://legacystore.app/app/379471852) | 155249 | 11.7 | **Fixed and retested.** Added missing URL and drawing APIs. Reached gameplay, completed a run (height 260), selected Again, and completed a second run (185). |

Rendering/performance anomalies are outside this pass, per the existing test
scope. A running process alone is not counted as working gameplay. No purchases,
account sign-ins, or personal-information submissions were made.

## Reproduced failures

### Canabalt

The normal launch raises:

```text
LC32: aggregate callback drawRect: requires metadata and a guest thread
```

At the guard in `LC32InvokeGuestSelectorAggregateFrame`, LLDB confirms
`signature.guestReturn == 'v'` and
`Dynarmic_guest_thread_is_registered() == false` on the failing thread.
The native stack runs from `CA::Transaction::release_thread` through layer
display and `UIView drawLayer:inContext:` into the guest callback bridge.
This narrows the failure to callback execution during native thread cleanup,
not missing callback metadata.

The native guest thread now flushes its pending Core Animation transaction
before retiring its JIT and releasing its guest stack. The exit syscall is
deferred out of `Jit::Run`, like native bridge calls, because the flush may
reenter guest drawing code. Existing post-retirement autorelease safety stays
intact; no callback suppression, cross-thread drawing relay, or game-specific
check was added.

`uikit-thread-exit-drawing` reproduces the original exception before the fix
and passes afterward through LC: exactly one worker-exit drawing callback,
correct pthread, non-null current graphics context, and correct CGRect.
`native-pthread-smoke` passes with 72 workers/72,000 increments, and the
aggregate-argument callback test passes. The normal LC URL launch reaches
the title menu. Gameplay/replay is not certified because the visible menu
is clipped; idb portrait rotation does not correct it.

### Super Hexagon

The normal-launch guest report records:

```text
Signal: SIGSEGV (11)
Emulator error: MemoryRead32 at guest address 0x100d31f8
pc 0x111365c0
```

The same failure reproduces under LLDB. The PC is in SuperHexagon's executable
(image base `0x11001000`, offset `0x1355c0`). After the rebuilt guest frameworks
shift allocations, the failing address is `0x100d11f8`; instruction tracepoints
pinpoint the dereference at `0x111365cc` (`ldr r0, [r0]`).

The fault is intentional, not a missing allocation or evidence of a bad copy:

1. AIR calls `mmap(NULL, count * 4, PROT_NONE, MAP_SHARED | MAP_ANON, ...)`.
   The memory watch confirms a protected page at `0x100d1000`; its backing exists
   but guest read permission is correctly denied.
2. Its table at `0x119c5d20` contains consecutive addresses into that page.
   A load through one of these addresses is meant to initialize a value lazily.
   This matches Adobe's published
   [AOTLazyEvalGuard implementation](https://github.com/adobe/avmplus/blob/master/aot/AOTCompiler.cpp),
   which computes a value and redirects its table entry after a guarded load.
3. The game's guard setup calls `thread_get_exception_ports` for
   `EXC_MASK_BAD_ACCESS`. A tracepoint immediately after that call at
   `0x11432914` records `r0 = 0x2e` (`KERN_NOT_SUPPORTED`), and its error branch
   returns before calling `thread_set_exception_ports`.
4. LiveExec32 deliberately returns unsupported from these APIs rather than
   installing ARM32 handlers on the host's ARM64 exception ports. Guest memory
   faults currently terminate execution instead of delivering a guest Mach
   exception and resuming its repaired ARM32 state.

A proper fix therefore needs virtual guest exception-port registration,
`EXC_BAD_ACCESS` delivery, guest thread-state repair, and precise fault retry.
It is not implemented in this pass. Making the guard page readable would skip
the required initialization and is not a valid fix. Diagnostic memory-watch
build flags were removed afterward; the normal runtime was rebuilt.

### NinJump

The live debugger captures the lazy-binding abort directly:

```text
Symbol not found: _CFURLCreateAbsoluteURLWithBytes
Referenced from: NinJump.app/NinJump
Expected in: /System/Library/Frameworks/CoreFoundation.framework/CoreFoundation
```

The normal simulator report also shows the guest-crash exception path, but its
final native failure is in uncaught-exception formatting. LC's saved `error`
preference still contained Super Hexagon's earlier report; it must not be used
as NinJump's cause. The LLDB capture establishes the missing symbol independently.

Implemented `CFURLCreateAbsoluteURLWithBytes` with byte-buffer marshalling,
base-URL ownership, and the native compatibility-resolution flag. Retesting
then exposed a second missing import, `CGContextShowGlyphs`, when starting a
game. Added that bridge and NinJump's related missing CoreGraphics imports:
character spacing, cubic curves, layer creation/context retrieval/release,
and drawing a layer at a point (plus matching layer retain support).

Validation:

- Native and ARM32 `corefoundation-url-propertylist`: pass, including exact
  byte lengths, non-UTF-8 encoding, relative resolution, and compatibility mode.
- Native and ARM32 `coretext-graphics-font`: pass, including current-position
  glyph drawing, empty input, bitmap synchronization, and character spacing.
- Native and ARM32 `coregraphics-layer`: pass, including borrowed context
  identity, retain/release, drawing offsets, bitmap synchronization, and curves.
- Normal LC URL launch: menu → Play → dismiss shield tutorial → results →
  Again → second results. No crash; process remained alive. Slow menu input
  required a longer idb touch. No graphics/viewport workaround was added.
- Combined fixes: another NinJump run reached results (height 198).
- `check-uikit-compatibility-switch`: passes for both compatibility modes.
  The thread-exit transaction flush is lifecycle correctness and remains
  enabled in both modes.
- Final normal-build recheck: forced a clean host rebuild, refreshed the
  private simulator runtime, confirmed the diagnostic memory-watch string
  was absent, and reran the ARM32 URL, layer, font, pthread, aggregate callback,
  and thread-exit drawing tests successfully.

## Local evidence

Screenshots, verified download metadata, crash reports, process samples, and
debugger logs are under `tmp/small-games-20261005.StQIQl/` (ignored local files).
Each filename starts with its catalog copy ID. The app bundles and their
private simulator runtime remain available in LC for follow-up testing.
All debugger sessions detached and exited. The test app was terminated after
the final screenshot/status check to release simulator CPU usage.

## October 6: library expansion and four additional games

Added **99 functions**, independently of the October 5 fixes above. The exact
list is in [`test/library_expansion_symbols.txt`](../../test/library_expansion_symbols.txt).
These are typed bridges to native implementations, not success-returning stubs.

| Library | Added functions | Coverage |
| --- | ---: | --- |
| CoreGraphics | 73 | Object type IDs and retains; bitmap/image/color-space queries; ICC profiles; font and glyph metadata; path copying; even-odd drawing; CMYK colors; geometry and coordinate conversions. |
| ImageIO | 25 | Metadata/tag creation, copying, editing, namespace registration, XMP serialization, image metadata round-trips, and copying an image source into a destination. |
| CoreFoundation | 1 | `CFSocketCreateWithNative`, plus read/write/accept callback support shared with the existing `CFSocketCreate` bridge. |

Geometry results are narrowed from native doubles to ARM32 floats. Owned and
borrowed CF results retain their respective ownership contracts. ImageIO's
five-argument tag constructor uses five wire slots; error pointers write only
the guest's four-byte proxy. Native destination mutations invalidate the guest
data cache. CFSocket accept callbacks marshal a four-byte descriptor, while
read/write callbacks receive a null data argument.

### Export and regression checks

- All 99 additions exist in both the iOS 10.3 ARM32 SDK exports and the built
  guest frameworks; `check-library-expansion-symbols` now participates in
  `check-symbols`.
- ImageIO export audit: 367 string constants and 51 functions pass.
- Existing public-constant/public-export, generated-public, generated-UI/media,
  and graphics compatibility audits pass. No new constants were needed for
  the checked sets. Some apparent header-only gaps are macOS-only declarations;
  they were not exported as pretend iOS APIs.
- New native and ARM32 tests pass: `coregraphics-queries` (31 checks),
  `imageio-metadata` (17), and `corefoundation-socket-native` (9). These cover
  pixel synchronization, float layouts, CF identity/ownership, XMP/JPEG
  metadata, error-slot guards, descriptor ownership, callback data, and context
  lifetime.
- Existing ARM32 socket, URL, graphics-layer, graphics-font, ImageIO round-trip,
  and pthread tests pass. The pthread smoke test completes 72,000 increments.
- The ImageIO round-trip runner needs `SIMCTL_CHILD_TMPDIR=/private/tmp` for its
  temporary-file test. Without this, the same setup failure also reproduces on
  the previous private runtime. With the writable directory, all 29 checks pass.
- Host and changed guest frameworks build successfully; UIKit compatibility
  build checks pass in modes 0 and 1; `git diff --check` passes.

This is not complete framework coverage. For example, ImageIO block-based
metadata enumeration, callback-heavy CoreGraphics APIs, GLKMatrixStack, custom
allocator context support (`kCFAllocatorUseContext`), and guest Mach exception
delivery remain outside this batch. The existing Super Hexagon failure above
is not fixed by these additions.

### Additional game results

All four copies came from Legacy Store and are below 17 MB (44.2 MB combined).
Catalog size/SHA-1, ZIP integrity, and unencrypted ARM32 slices were verified.
Each was installed as a new `library<COPY>.app` app-bundle symlink. LC created
its metadata automatically. The private `lc32-library-games-20261006.app`
runtime uses the new CoreFoundation, CoreGraphics, and ImageIO guest frameworks
and rebuilt host shared framework; unrelated packaged guest frameworks were
preserved. Legacy SDK fallback, Classic Mode, simulator, and input constraints
are unchanged from the configuration above.

| Game / version | Catalog copy | IPA MB | Observed result |
| --- | --- | ---: | --- |
| [Labyrinth 1.8.0](https://legacystore.app/app/284571899) | 6249 | 5.7 | Menu → Play → Alphabet A–M opens the first maze without a crash. Tilt control and level completion are untested. |
| [Flick Kick Field Goal 1.5.0](https://legacystore.app/app/351707231) | 199348 | 16.9 | Original copy intermittently deadlocks entering Arcade. A separately installed, user-approved ARMv7 game patch reaches Arcade and survives pause → menu → Arcade; **the original game and shared runtime remain unchanged**. See shutdown investigation below. |
| [Solipskier 1.2](https://legacystore.app/app/383281764) | 10251 | 13.9 | A touch-and-drag run reaches results (score 163, time 5.31 seconds). Restart returns to the skier scene without a crash. |
| [Sneezies 1.7](https://legacystore.app/app/298155609) | 282167 | 7.7 | Classic mode reaches level 1; a touch triggers a chain reaction popping four bubbles. No crash; later levels are untested. |

No newly missing import was observed on the successful paths. This does not
mean these games exercise all 99 new APIs. Orientation, rendering, and slow
startup remain outside this smoke-test pass; no game-specific display hooks
were added. Optional accounts were not used.

### Flick Kick: audio shutdown lock inversion (isolated game patch)

A three-second process sample and LLDB attachment independently show the
main thread waiting in `DispatchAudioQueueDispose` for active callbacks/users
to finish. CoreAudio's output callback is waiting in `SubmitGuestCallback`,
while a guest worker is parked in `GuestPsynchMutexWait`. The native callback
executor has an active job. A fresh-launch reproduction and read-only guest
stack inspection now establish the complete cycle:

- Queue 1's user data is `OggStream` at `0x1202bc00`; its `MabMutex` is at
  `+0x304`, exactly the blocked guest address `0x1202bf04`.
- The callback executor is inside `OggStream::audioCallback`, returning to
  ARMv7 `0x10d6c9` after `MabMutex::Lock`.
- `OggStream::~OggStream` acquires that same mutex, frees buffers and calls
  `AudioQueueDispose(queue, true)` **before unlocking it**. The main thread
  waits for the callback, and the callback waits for the main thread's lock.
- An independent native simulator AudioQueue probe also waits for a blocked
  callback: disposal returned after 3.006 seconds, only after the probe's
  lock-owning worker released the mutex. This is not evidence that the runtime
  should return early or free buffers while callbacks still use them.

The existing guest lifecycle mutex is already unlocked before invoking native
disposal (confirmed in the packaged guest disassembly). No runtime callback
cancellation, forced success, or early buffer release was added.
After debugger inspection the process also aborted from a condition-variable
wait on that worker; this post-debugger abort is preserved separately and is
not claimed as a clean-launch reproduction of an independent crash.

With explicit user approval, a separate `FlickKickAudioTest.app` was cloned
under `tmp/audio-shutdown-20261006.WTmI3G/` and linked into simulator LC as
`flick-audio-test.app`. LC generated its metadata and separate data container
normally. Tests use the same private runtime, Legacy SDK (`131072`) and Classic
Mode. Only the ARMv7 destructor body is patched; this is a version-specific
experiment, not a distributed patch or a runtime-wide fix.

The replacement destructor sets the existing decoder-stopped flag under the
game mutex, releases that mutex, synchronously disposes the queue (including
its buffers), then clears decoder state and destroys the mutex. A callback
which was waiting can acquire the mutex, observe the stopped flag and return
before any decoder/user-data destruction.

The patch script checks the original executable's SHA-256 and non-PIE ARMv7
layout before changing the destructor. Original executable hash remains
`6f1e27e7247ded9522b86d9a78706d914036cc35ffc469c7e91f5f65ac6df44c`;
patched hash is
`2580f0bb19c4049ba32d056077cd9dfcbcfbf8a39f227391d7ce9ca780670f16`.
The original IPA, original installed game, shared runtime and other pending
source changes are untouched by this experiment. Audio quality, full rounds
and real-device behavior have not been validated.

The isolated patch source (`ogg-shutdown.s`), guarded binary patcher
(`patch-game.py`), native comparison probe, debugger logs and screenshots are
in `tmp/audio-shutdown-20261006.WTmI3G/`. The first two debugger-forced overlap
attempts were inconclusive (no callback, then an unavailable-condition error),
not successful stress tests.

The corrected controlled-overlap test **passed** (`patched-stress3.txt`):
LLDB suspended the output callback on guest executor thread 3 immediately
before entry into game code. Main-thread disposal then reported queue 1 with
`activeCallbacks = 1`. After resuming the callback, the executor became idle
with no active job, disposal returned, and the game completed Loading and
reached Arcade (`patched-stress3-complete.png`). All suspended threads were
resumed and the debugger detached. Together with the normal first entry and
pause → menu → Arcade repeat, this validates the targeted shutdown ordering;
it does not establish a general runtime fix for other games.

October 6 evidence is under `tmp/library-games-20261006.RNM1YW/`: symbol audits,
native/guest test logs, download metadata, screenshots, the audio-hang process
sample, and detached LLDB session logs.
The game was terminated after testing to release simulator CPU usage; the app
bundles and private runtime remain installed for follow-up.

## October 7: five more light games

Flick Kick's audio investigation and isolated game patch were left unchanged
at the user's request. This pass uses the same iPhone simulator, Legacy SDK
fallback (`131072`), Classic Mode, and UIKit compatibility enabled. None of
these five executables declares an SDK in its Mach-O load commands; the
fallback is not a claim about their original build SDK.

All five copies came from Legacy Store and total 58.9 MB compressed. Catalog
size/SHA-1, ZIP integrity, and unencrypted ARM32 slices were verified before
extracting only the app bundles. Separate `light<COPY>.app` symlinks and data
containers preserve existing installations and saves. LC generated all five
`LCAppInfo.plist` files and data-container UUIDs automatically. As in the
earlier batches, the initial default device-runtime selection was unsuitable
for the simulator; each test copy was explicitly switched to the private
simulator runtime before testing. No global emulator preference was changed.

| Game / version | Catalog copy | IPA MB | Observed result |
| --- | --- | ---: | --- |
| [Drop7 2.4.2](https://legacystore.app/app/299940763) | 194033 | 5.8 | **Reached gameplay.** Declined optional upgrade, entered Normal mode, and made three moves. The board changed and the score reached 60. No crash; a full round is untested. |
| [Hook Champ 1.60](https://legacystore.app/app/334626134) | 85189 | 17.8 | **Reached gameplay.** Skipped intro, declined online score submission, selected the Wimpy Idol / Stone Wimpy, advanced tutorial dialogue, and held the walk control. The character and scene advanced without a crash. Tutorial completion is untested. |
| [iBlast Moki 1.0](https://legacystore.app/app/329661219) | 48280 | 10.0 | **Startup crash, unresolved.** Reproduced normally and under LLDB in `-[NGPlatform _userLoggedIn:error:]`, reached through the delayed-perform shim. See callback finding below. |
| [Dizzypad 1.4.1](https://legacystore.app/app/357104694) | 169048 | 8.4 | **Startup crash, unresolved.** Native `-[UIWebView setDelegate:]` faults at address `0x20`. An independent native probe does not reproduce it. |
| [Pocket God 1.31](https://legacystore.app/app/301387274) | 16144 | 16.9 | **Startup sort crash fixed and retested.** Normal LC URL launch now reaches the Episode 31B update panel and stays running. The panel is undersized; a tap on the visible Go button did not advance it. Gameplay remains unverified; display/input investigation is outside this pass. |

### Pocket God: function-pointer array sorting

Both the game and a new standalone ARM32 regression test originally aborted
with `cannot forward guest -[NSMutableArray sortUsingFunction:context:]:
unsupported argument encoding`. Pocket God invokes this from its loading
worker. The generic method forwarder cannot marshal a guest function pointer
and opaque context as ordinary native arguments.

`NSMutableArray+LC32Sorting.m` now implements this method in the guest and wraps
the comparison function with the existing `sortUsingComparator:` block bridge.
The callback and context stay in the guest; the existing bridge handles object
identity and the signed comparison result. This requires no game-name checks,
host selector dispatch branches, or new callback-lifetime mechanism.

Validation:

- Native simulator `array_sort_function.m`: passes.
- ARM32 test on the prior runtime: reproduces the same unsupported-encoding
  abort. The prior Foundation binary is retained in the evidence directory.
- ARM32 test after updating Foundation: passes with guest exit code 0.
  Coverage includes ascending/descending order, duplicate values, in-place
  mutation, opaque/null contexts, nested sorting, empty/singleton arrays,
  guest-defined objects, and their deallocation.
- Existing `lc32-block-bridge` and `lc32-thread-perform`: pass with guest exit
  code 0. The block suite includes worker-thread callback coverage.
- Foundation and regression-test builds succeed; the newly introduced
  noescape annotation warning was corrected. Existing linker warnings remain.
- Pocket God was retested through the normal URL launch, without a debugger.
  Only Foundation was replaced in the private runtime's guest frameworks;
  the packaged UIKit and other guest frameworks were preserved.

### Remaining findings

**iBlast Moki:** the crash reads through `0x203`, used as the `error:` object
in `-[NGPlatform _userLoggedIn:error:]`. The delayed-perform shim calls the
selector with one object argument, while the game's method expects two.
[Apple documents this delayed-performing API](https://developer.apple.com/documentation/objectivec/nsobject-swift.class/perform(_:with:afterdelay:)?language=objc)
for zero or one object argument. A separate native simulator probe scheduled
ten two-argument callbacks through that API; the second argument contained
non-null incidental values, not a guaranteed nil. This is evidence against
blindly clearing extra arguments as a general Foundation correction. It does
not establish historical ARM32 Foundation behavior. No game patch or global
delayed-perform change was made.

**Dizzypad:** LLDB caught an invalid write inside native `UIWebView setDelegate:`.
Both isolated native `init` and `initWithFrame:` followed by `setDelegate:nil`
completed successfully on this simulator. The game-specific initialization
path therefore still needs investigation; this is not classified as a proven
simulator-only framework failure. Static import inspection also found the
unimplemented `CGPathAddArc`, but execution has not yet reached a missing-symbol
failure for it. No claim is made that adding that export would fix startup.

Evidence, source metadata, test logs, native probes, and screenshots are in
`tmp/light-games-20261007.Y3UEjS/`. All game input was simulator-only through
idb, with no Mac keyboard/mouse/focus use. LLDB sessions were bounded and
detached. No account signup or purchase was performed. This pass did not
change the Flick Kick patch or audio runtime.

Before committing on October 9, the host build, UIKit compatibility compile
checks in modes 0 and 1, 99-function library export audit, ImageIO export audit,
and `git diff --check` were rerun successfully. Gameplay was not rerun during
the commit-only pass.
