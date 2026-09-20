# Approved-source game follow-up — September 26, 2026

This continues the [approved-source audit](skipped-game-sources-2026-09-26.md).
Tests use normal `dev` (base `bf3e49b`), not the portrait-canvas experiment,
on the iPhone 17 Pro Max / iOS 27 simulator. Classic Mode is enabled and the
original SDK is selected where recorded in the executable. Very old binaries
without an SDK load command use the existing SDK 2.0 floor.

The continuation is **crash-only** at the user's request. Blank, clipped,
rotated, or otherwise incorrect rendering is excluded from this fix pass;
it is not counted as fixed or as proof of a Classic Mode configuration cause.

## Installation and scope

Installed app bundles only: Family Guy: Uncensored 1.1.1 (copy 17368), Crash
Bandicoot Nitro Kart 3D 1.7.7 (17357), Super Monkey Ball 1.3 (28142), Boomlings
1.43 (70193), Tiny Death Star 1.4.2 / build 1.4.3019 (IPA Archive 9404),
Jumping Finn Turbo 1.1.1 (52262), and Hero of Sparta 1.30 (60348).
ZIP integrity and catalog hashes were checked, and ARM32 slices are unencrypted.
Existing game bundles and saves were not replaced.

LC generated each game's `LCAppInfo.plist` on its first launch; these were not
hand-authored. The default runtime is a device build, so simulator testing uses
a temporary per-game runtime selection. A few setup launches showed LC's
`App bundle not found! Unable to read LCAppInfo.plist.` error; the game metadata
was present, and dismissing the error / retrying the launch worked. Those failed
setup attempts do not count as game results. The launch cause was not resolved
in this pass.

Normal launch/visual checks use LC URLs. Direct `simctl --wait-for-debugger`
launches are diagnostic only: they do not reproduce the Classic Mode viewport
and are not used to assess layout. Temporary SDK/runtime settings are backed up
and restored. No Mac keyboard, mouse, focus, or VPN changes are used.

## Results

| Game | Reproduced failure | Change / current result |
| --- | --- | --- |
| **Super Monkey Ball 1.3** | Tapping the title aborts on missing `_CGColorSpaceCreateWithName`; stack runs through `gfx::TextRenderer::CreateBitmapContext` while constructing `smb::MainMenu`. | Added a real guest/host CoreGraphics bridge. Repeated the same tap in Classic Mode, reached Mode Select, character selection, Monkey Island, level selection, and the tutorial welcome screen. No crash at the former trigger; gameplay/tilt and real-device behavior are not yet validated. |
| **Boomlings 1.43** | Format/decryption failures, duplicate mirrored classes, a freed StoreKit delegate, and a rootless menu-class stub. | Earlier fixes restore `%&` parsing and guest-visible decryption bytes. This continuation serializes native class publication, removes temporary ownership from `SKRequest.setDelegate:`, and gives the guest menu stubs their proper superclasses. A clean LLDB startup check is crash-free; normal Classic Mode launch reaches username entry. **Startup repaired in the simulator; no username submitted or level played.** See the detailed continuation below. |
| **Real Racing 3 1.0.2** | Missing CoreText/CoreGraphics symbols, followed by native alert-layout and background-thread alert-presentation crashes. | Added the missing font/typesetter/glyph/bitmap functions; the binary's CoreText/CoreGraphics import audit is now clean. Extended the existing scoped layout policy to the native alert root, and route guest `UIAlertView.show` calls onto the main thread. A 50-second normal Classic Mode retest remains running and displays `Setting not found 'DYNAMIC_CAR_REFLECTIONS'`. **Not playable yet; settings/device-profile remains unresolved.** Clipping is excluded from the continuation. |
| **Family Guy: Uncensored 1.1.1** | Guest null read in `CGraphics_HAL::ClearBuffers` during `CGameApp::OnInit`. Static inspection finds the graphics-backend member is null. | The earlier short `libstdc++.6` problem is not the current blocker with this runtime. Graphics initialization still needs investigation; no game-specific workaround added. |
| **Crash Bandicoot Nitro Kart 3D 1.7.7** | Native startup throws because `MainWindow.nib` cannot be loaded. | Both approved copies 17357 and 16721 declare `NSMainNibFile=MainWindow` but contain no nib. Second copy downloaded and inspected, not installed over the first. Need to distinguish legacy UIKit behavior from incomplete packaging before changing startup behavior. |
| **Tiny Death Star 1.4.2** | No startup crash in the 100-second follow-up. | Reaches the age-selection screen. No age was selected or submitted; gameplay is still untested. |
| **Fragger DS 1.9.1** | Native thread performing aborts while marshalling `preloadMusic:`: the game declares its object argument as `^@`. | Generalized the existing notification object-callback adapter to native thread performs. Kept the original receiver/selector and API's object semantics without weakening general pointer marshalling. A 45-second LLDB retest hits no crash breakpoint; normal LC launch remains alive at the splash after 30 seconds. **Reproduced abort fixed; gameplay not verified.** |
| **Plants vs. Zombies 2 3.2 / build 3.2.1** | `performSelector:onThread:` targets a not-yet-started `NSThread`; fixing this exposes missing `CFNotificationCenterRemoveEveryObserver`. | Queue pre-start performs until the native thread exists; support asynchronous and synchronous delivery. Added filtered and complete CF notification removal with registration lifetime cleanup. A 90-second LLDB retest hits no crash breakpoint. A separate 90-second normal LC launch remains alive but black. **Two reproduced blockers fixed; black output excluded, not a successful gameplay result.** |
| **Spooky Pop 0.2.10** | Missing `CFAllocatorCreate`, then `CTFontCopyFamilyName` and other imported CF/CoreText APIs. | Added guest allocator callbacks/no-copy-data cleanup, tokenizer APIs, and the remaining imported font/run/typesetter functions. Import audit is clean. No crash breakpoint in 65 seconds; a separate 50-second normal launch reaches the level map. **Startup blockers fixed; no level played.** |
| **Jumping Finn Turbo 1.1.1** | No startup crash reproduced. | Newly installed from the approved catalog. A 35-second LLDB check is clean; normal launch reaches the New Game menu after 45 seconds. Gameplay untested; visual layout excluded. |
| **Hero of Sparta 1.30** | No startup crash reproduced. | Newly installed from the approved catalog. A 35-second LLDB check is clean; normal launch remains alive after 45 seconds with a blank intro rectangle. Rendering/intro behavior excluded; no claim that gameplay works. This is not the separate 1.06 audio-symbol case. |
| **Cut the Rope 1.0** | Guest ownership teardown aborts during analytics unarchiving. | Trace narrows this to a native-created `CCAnalyticData` mirror: the guest autorelease drains its last logical reference while its mapping is still marked pinned. Correct ownership transfer during decoding still needs investigation. No refcount clamp or ignored abort added. **Unfixed.** Other versions' earlier results do not establish compatibility for 1.0. |
| **World of Goo 1.3** | Framebuffer creation sends `setupView:` to an invalid delegate; observed `UIImage`/`__NSCFType` receivers and an invalid guest memory read. | `IPhoneGraphics::CreateView` allocates/initializes/autoreleases `IPhoneEAGLViewSettings`, then stores it in the view's non-retaining delegate. The guest trace confirms its sole reference drains before a later `layoutSubviews` sends `setupView:`. It has no native peer at that point. Need to establish the legacy layout/pool timing before choosing a compatibility change; no fake selector, blanket delegate retention, or exception suppression added. **Unfixed.** |

### Implementation boundaries

- The shared object-callback adapter lives in `ObjectCallbacks.mm`; it is a
  guest-only host-selector hook, not another class-specific branch in
  `LC32InvokeHostSelector`.
- Custom CF allocator callbacks execute against guest memory. Native data
  retains a copied backing buffer and an owner token, then releases the
  original guest bytes and allocator exactly once when storage dies.
  Native allocation never receives an ARM32 buffer pointer.
- Allocator support is not complete: custom parent allocators and
  `kCFAllocatorUseContext` are rejected, and this does not apply custom
  allocation policies to every existing CF constructor. Native debug
  descriptions do not invoke guest `copyDescription` callbacks.
- CF notification removal preserves the existing local-center bridge.
  Arbitrary non-object sender tokens are not newly supported.

## Regression checks

- Host and guest framework builds: pass.
- CoreGraphics and CoreText export audits: pass.
- ARM32 `coregraphics-bitmap`: pass, including named RGB/gray/sRGB spaces,
  unknown/null names, and drawing after releasing the source color space.
- ARM32 `string-format`: pass, including all three new `%&` cases.
- ARM32 `coretext-graphics-font`: pass; native and guest text widths agree
  (`164.3391`, `328.6782`, `246.5087`) for plain, double-size, and affine-scaled
  fonts, with source references released before measurement.
- Extended that test to cover descriptor ownership, glyph mapping, missing
  glyph output, font metrics, float-sized bounds/advance arrays with canaries,
  double total advances, typesetter/line lifetimes, independent stable glyph
  and position pointers, bitmap dimensions, and positioned-glyph drawing.
  Native ASan/UBSan and ARM32 runs pass; printed layout metrics agree.
- ARM32 `string-bytes`: pass, including the previously failing guest-visible
  data case, mutable-string output, UTF-16/embedded NUL, empty data, and invalid
  UTF-8. The focused native data-input ASan/UBSan test also passes. The entire
  existing string suite is not a native macOS oracle: its deprecated `cString`
  cases hit a native macOS exception, so only the focused new cases were used
  for that native comparison.
- ARM32 `class-cluster-reuse`: serial and concurrent tests pass with zero
  failures after the initializer change.
- UIKit compatibility-switch checks pass with both `0` and `1`; the scoped
  alert hosting and guest alert-show adapters remain available in both modes.
- ARM32 and native `thread-perform`: pass, including misdeclared object
  callbacks and asynchronous/synchronous delivery queued before thread start.
- ARM32 `corefoundation-notifications`: pass for delivery, filtered removal,
  wildcard removal, and preserving another observer's registration. The
  focused native ASan/UBSan comparison also passes.
- ARM32 `corefoundation-allocator`: pass for context layout, callback lifetime,
  allocate/reallocate/preferred size, null/default allocators, copied-data
  independence, and exactly-once no-copy cleanup, including empty data.
  Native supported-case ASan/UBSan comparison passes. Unsupported context
  version rejection is tested only against the guest implementation.
- ARM32 and native ASan/UBSan `corefoundation-tokenizer`: pass for token ranges,
  end-of-input, and language detection.
- Extended `coretext-graphics-font` again: font copies/attributes, underline
  thickness, double-width typesetter/flush calculations, copying full/partial
  glyph/position/advance/string-index arrays with canaries, and glyph drawing.
  ARM32 and native ASan/UBSan comparisons pass.
- Existing ARM32 `notification-selector` suite: 27 checks, zero failures,
  including foreign-thread delivery, weak observers, and self-removal.
- Host-selector registry and UIKit compatibility-switch checks pass after
  moving/generalizing the object-callback adapter.
- Existing ARM32 `corefoundation-common-wrappers`: pass against the cleaned
  final runtime (including data ranges, numbers, ownership, and autorelease).
- The broader `corefoundation-low-risk` suite is **not passing**: it traps in
  native `CFUUIDGetUUIDBytes`, called by `CFFileSecuritySetOwnerUUID`, with a
  mismatched CF type ID. The preserved September 22 runner reproduces the
  same failure with the same test binary. This is an existing UUID/file-security
  bridge gap, not a newly fixed path; its later checks did not run.
- A separate pre-existing gap was found: `CGBitmapContextGetData` returns null
  for contexts created with a null data pointer. Positioned-glyph regression
  uses an explicit guest-owned pixel buffer; internally allocated pixel access
  is **not fixed** by these additions.
- The bitmap regression also emits the runtime's guarded dead-receiver release
  diagnostics; no assertion fails. Those diagnostics were not investigated here.

## idb environment update

The installed Homebrew companion 1.1.8 failed HID initialization by looking for
SimulatorKit under `Contents/Developer/Library/PrivateFrameworks`. A cached 1.5.7
companion allowed the initial crash reproduction. At the user's request:

- Updated `~/.venv`'s `fb-idb` from 1.1.7 to **1.6.2**. No other Python packages
  changed. `pip check` reports unrelated pre-existing conflicts involving
  py-utlx, rsactftool, and autodecrypt; these were left unchanged.
- Updated Homebrew `facebook/fb/idb-companion` from 1.1.8 to **1.6.2**, with
  automatic cleanup disabled so the previous installed version remains.
- Verified the new companion loads
  `/Applications/Xcode.app/Contents/SharedFrameworks/SimulatorKit.framework`
  and accepts HID taps. Used the updated venv client and companion for the
  successful Super Monkey Ball menu/tutorial retest.

## Evidence and remaining work

Ignored evidence is under `tmp/game-followup-20260926/`: baseline/debug logs,
metadata backups, build/regression logs, and screenshots. Key files:

- `monkey-classic2-lldb.log`: pre-fix title-tap missing-symbol crash.
- `monkey-fixed1-lldb.log`: post-fix watch, no crash breakpoint hit; detached.
- `monkey-fixed-menu.png`, `monkey-fixed-select2.png`, `monkey-fixed-world.png`,
  `monkey-fixed-level.png`: menu → character → levels → tutorial welcome.
- `eval70193.app-fixed-debug1/`: remaining Boomlings archive exception.
- `eval20849.app-debug1/`: Real Racing 3 missing-symbol baseline.
- `eval20849.app-fixed-debug1/`: Real Racing 3's next missing symbol.
- `eval20849.app-copy-font-debug/`, `eval20849.app-typeset-debug/`,
  `eval20849.app-racing-cg-debug/`: successive Real Racing blockers.
- `eval20849.app-layout-origin2/lldb.log`: assertion receiver identified as
  `_UIAlertControllerPhoneTVMacView`, not an arbitrary guest view.
- `eval20849.app-racing-alert-fixed/screen.png`, `racing-alert-live.png`:
  post-fix missing-settings dialog, with remaining clipping visible.
- `eval70193.app-archive-origin5/`: invalid archive and guest caller at
  `Boomlings + 0x8e320` (`loadDataFromFile:`); bundled `CCData.dat` is 25,280 bytes.
- `string-data-before.log`, `string-data-final.log`:
  minimal data-to-string regression before/after the fix.
- `eval70193.app-boom-data-fixed/`, `eval70193.app-data-fixed-debug/`:
  later Boomlings failures, not a successful gameplay result.
- `eval70193.app-data-fixed-archive/lldb.log`: post-fix game archive has a
  valid `bplist00` header and decrypted length of 25,271 bytes.
- `eval9404.app-tiny-followup/screen.png`: untouched age-selection gate.
- `idb-1.6.2.log`: SimulatorKit load and successful HID requests.
- `eval157561.app-remaining-fragger/`, `eval157561.app-fragger-object-fixed/`:
  before/after the object-argument crash; `eval157561.app-fragger-classic-fixed/`
  contains the separate normal-launch screenshot.
- `eval267926.app-pvz-thread-diag-long/`,
  `eval267926.app-pvz-prestart-fixed/`,
  `eval267926.app-pvz-notifications-fixed/`: the pre-start thread failure,
  subsequent missing removal API, and clean 90-second crash watch.
- `eval267926.app-pvz-classic-fixed/`: alive with excluded black output.
- `eval285633.app-spooky-allocator-fixed/`,
  `eval285633.app-spooky-text-fixed/`,
  `eval285633.app-spooky-classic-fixed/screen.png`: successive startup blockers,
  clean crash watch, and level map. `spooky-missing-cf-ct-cg.txt` is empty.
- `eval52262.app-finn-classic/`, `eval60348.app-sparta-classic/`: new-game menu
  and blank intro, respectively; not gameplay results.
- `eval222781.app-cut-release-trace/`: analytics ownership teardown trace.
- `eval30269.app-remaining-goo/`, `eval30269.app-goo-lifetime-trace/`: invalid
  delegate selector/memory failure at the same framebuffer callback.
- `eval30269.app-goo-guest-lifetime2/stderr.log`: the settings delegate is
  autoreleased with guest count 1 and later released with count 1, with no
  intervening retain. Disassembly at `0x127130`–`0x127164` identifies
  alloc/init/autorelease/setDelegate, and the setter at `0x1304c4` only stores
  the pointer. Diagnostic-only trace changes were removed afterward.
- `final-thread-perform.log`, `final-corefoundation-allocator.log`,
  `final-corefoundation-notifications.log`, `final-corefoundation-tokenizer.log`,
  `final-notification-selector.log`, `final-coretext-graphics-font.log`:
  successful ARM32 focused/regression runs.
- `clean-common-wrappers.log`: successful existing CF regression suite.
  `clean-low-risk.log`, `low-risk-prior-runtime.log`, and `low-risk-lldb.log`:
  the pre-existing UUID/file-security trap on current and prior runtimes.

Remaining reproduced blockers are **Cut the Rope 1.0, World of Goo,
Family Guy: Uncensored, Crash Bandicoot Nitro Kart 3D, and Real Racing 3**
(the last is a settings gate rather than a current crash).
The other approved-source candidates remain queued: Prince of Persia: Warrior
Within HD, Hero of Sparta II, Where's My XiYangYang?, and an explicitly
different-version Cling Thing candidate. Hero of Sparta 1.06 is also distinct
from the tested 1.30. Doodle Truck and Mini Car Champion's rendering/touch-only
reports are excluded. See the source audit for versions/download IDs.
No full-set compatibility claim or real-device verification is made.

After testing, SDK/runtime/Classic Mode/container settings were verified against
the backups for all 13 tested bundles. LC's subsequently generated icon-cache
metadata was preserved. The temporary LC runtime symlink was removed; the
cleaned local runtime artifact and installed game bundles/saves remain.
All LLDB sessions started for this continuation detached and exited. The
existing Xcode debugger and already-running idb companion were left alone.
Source/report changes were uncommitted at the testing handoff; nothing was pushed.

## Boomlings continuation

Boomlings 1.43 remains on its original SDK 6.0 (`393216`) with Classic Mode
enabled. No save reset, desktop input, account creation, or purchase was used.

Three additional causes were isolated and fixed:

1. **Concurrent native class publication.** Two guest threads could both
   allocate an `AdColonyReachabilityQuery` mirror before either registered it.
   Native registration does not reserve the name during allocation. A recursive
   publication mutex and a non-hooking `objc_lookUpClass` recheck now serialize
   preparation/registration; guest-class flags are set before publication.
   The superclass is resolved before acquiring the lock. A focused eight-worker,
   sixteen-round regression reproduced duplicate parent/child classes and a
   crash before the change, then passed with one class per name afterward.
2. **StoreKit delegate lifetime.** `MKStoreManager` overrides `retain` as a no-op
   but inherits `release`. The ARC-generated `SKRequest.setDelegate:` shim
   released its temporary argument before passing the saved native pointer to
   StoreKit. This reproduced both `objc_storeWeak` faults and native release
   faults. A small MRC setter forwards the non-owning delegate without changing
   guest ownership; native StoreKit still handles its weak reference. No
   singleton-name check, blanket delegate retention, or ignored exception was
   added. The isolated regression crashed before and passes after, including
   ordinary delegate zeroing after draining both native and guest temporaries.
3. **Menu stub inheritance.** `UIMenuElement` and `UICommand` had implementations
   but no declarations in the iOS 10 SDK build. They became zero-size root
   classes. A modern `UIMenu` passed into the legacy text responder mapped to
   the first stub and aborted on missing `initWithHostSelf:`. Compatibility
   declarations now establish `NSObject → UIMenuElement → UICommand`. A hierarchy
   regression fails before and passes after; this is a bridge-type correction,
   not a new UIKit behavior hook.

Two clean, uninstrumented LLDB runs each completed 55 seconds without a crash.
A separate normal LC URL launch remained alive for 45 seconds and showed the
username-entry screen, including the native text-editing menu which previously
triggered the abort. No username was submitted, so gameplay and network-backed
features remain untested. Earlier intermittent nil `appendString:`/sprite-cache
exceptions did not recur in these final checks; their individual causes were
not separately proven, and this is not a full compatibility claim.

Host and full guest framework builds pass. Focused `host-class-publication`,
`storekit-delegate`, and `uikit-menu-classes` regressions pass, as do existing
`guest-proxy-lifetime`, `root-dealloc-reentry`, and `arc-proxy-lifetime` checks.
The broad test build was not counted as passing: it encountered an unrelated
`corefoundation-string-transform` link failure on `_NSFontAttributeName`.

Evidence under `tmp/game-followup-20260926/`:

- `boom-class-baseline3.log`, `boom-class-fixed1.log`: class-race before/after.
- `boom-storekit-baseline.log`, `boom-final3-storekit-delegate.log`: delegate
  crash before, singleton and ordinary weak-delegate checks passing after.
- `boom-menu-baseline.log`, `boom-final-uikit-menu-classes.log`: menu hierarchy.
- `eval70193.app-boom-cont-inprocess3/`: StoreKit weak-reference fault.
- `eval70193.app-boom-menu-diag1/`: confirmed rootless menu-class mapping.
- `eval70193.app-boom-clean-fixed1/` and `eval70193.app-boom-clean-fixed2/`:
  clean 55-second LLDB startup observations.
- `eval70193.app-boom-clean-classic1/`: normal-launch metadata, live process,
  and username-entry screenshot.
- `boom-complete-{host-class-publication,storekit-delegate,uikit-menu-classes}.log`:
  all three focused tests pass after refreshing artifacts from the full build.

Temporary diagnostic code was removed from both host bridge files.
Boomlings' final `LCAppInfo.plist` matches the pre-test backup byte for byte.
All debug/test processes started here exited; the temporary LC runtime symlink
was removed, while the clean local artifacts, app bundle, and saves remain.
The pre-existing Xcode debugger and idb companion were left running. These
additional changes were uncommitted at the testing handoff.

## Commit checkpoint — September 27, 2026

The tested changes were committed locally on `dev` at the user's request:

- `fc9c3ef`: CoreFoundation allocators, tokenizer APIs, and notification removal.
- `b99276b`: CoreGraphics/CoreText font, glyph, and typesetter support.
- `e118b70`: threaded callbacks, queued pre-start performs, and alert presentation.
- `3be1b5a`: Boomlings decoding, class publication, delegate lifetime, and menu stubs.

The reports are committed separately. No push was performed; compatibility
results and remaining limitations above are unchanged.
