# Issue-game follow-up — 2026-09-22

This is a partial crash-fix pass, not a full compatibility claim. No gameplay,
Mac mouse/keyboard automation, real-device retest, push, or GitHub issue changes.

## Saved work

The previously pending work was split into three local commits:

- `f0eb536`: route guest `make install` through the ramdisk packer.
- `66e6a5f`: publish legacy GL drawable storage created on render threads.
- `f01b6cc`: bridge AudioFileStream and complete the core AudioQueue operations.

The Core Data change described below was made in a subsequent pass.

## Downloads and installation

After the user enabled the VPN, restarted the throttled downloads from scratch.
Both completed and matched LegacyStore's byte counts and SHA-1 values. Copied
only the extracted app bundles into simulator LC; LC successfully created
`LCAppInfo.plist` and separate data containers on first launch.

| Game / issue | LegacyStore candidate | Verified bytes / SHA-1 |
| --- | --- | --- |
| [Scribble Hero #47](https://github.com/LiveContainer/LiveExec32/issues/47) | 2.0.2, [copy 204657](https://legacystore.app/ipa/204657), `com.mtvn.PaperWars` | 51,146,104 / `0d26eaeb553522500b144bcc8b1d7ced7a0d1a85` |
| [Godzilla: Strike Zone #48](https://github.com/LiveContainer/LiveExec32/issues/48) | 1.1.0, [copy 223429](https://legacystore.app/ipa/223429), `com.wb.godzilla.strikezone` | 101,458,122 / `04915cf102810443f8785e4cf09f8fd0d3fcf030` |

Scribble's three installable 2.0.2 catalog copies share the same checksum; one
is named `Scribble Hero mod.ipa`. This candidate may therefore be modified and
is not proven byte-identical to the reporter's copy. No binary was patched here.

Simulator: iPhone 17 Pro Max, iOS 27. Classic Mode enabled,
`LC32_UIKIT_COMPATIBILITY=1`, isolated runtime selected only for these two new
test copies. Initial LC metadata selected SDK 2.0 for both, despite the binaries
declaring SDK 6.1 (Scribble) and 7.1 (Godzilla). Scribble's final URL-launch
retest explicitly uses its original SDK 6.1. Godzilla's diagnostic reproduction
uses the auto-selected legacy 2.0 override. Debugger launches are not geometry
validation; normal startup retests use the LC URL.

## Scribble Hero: Core Data accessor crash fixed, later blocker remains

The issue's `WeakReferencedObject queueDidStart:` forwarding failure no longer
reproduces with the existing forwarding bridge. Fresh launch instead aborts on:

```text
-[KTElementRecord setSessionId:]: unrecognized selector
-[KTCoreDataQueue enqueue:]
-[KTTransferQueue onEnqueueElement:]
```

The binary declares `KTElementRecord` as an `NSManagedObject` subclass with five
object-valued `@dynamic` properties and no compiled accessors. Native Core Data
can generate native methods, but those do not supply ARM32 implementations.
The generated guest `+resolveInstanceMethod:` bridge alone cannot fill this gap.

Added a framework-local `NSManagedObject` resolver for object-valued `@dynamic`
properties. It installs correctly typed ARM32 getters/setters, binds the exact
property key, and uses primitive storage wrapped in Core Data access/change
notifications. This preserves fault firing, KVO and inverse relationships.
It follows Apple's [custom accessor protocol](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/LifeofaManagedObject.html).
It does not alter UIKit, disable the game's analytics, or invent scalar/block
accessor ABIs. Scalar properties and generated to-many mutation selectors are
outside this patch's scope.

Verification:

- Unmodified-runtime regression reproduces `setSessionId:` with a minimal
  programmatic Core Data model, before introducing the bridge.
- Final ARM32 regression: **20 checks, zero failures**, guest exit 0. Includes
  inherited properties, uppercase `URL`, boxed 64-bit values, KVC interoperability,
  exactly one KVO change with old/new values, save/reset/refetch, fault firing,
  to-one relationships/inverses, nil assignment, and updated state.
- The same 20 checks pass against native macOS Core Data.
- Existing Core Data merge-policy regression: **11 PASS**; NSProxy/forwarding
  regression: **59 checks, zero failures**. Both guests exit 0.
- Guest-framework build and `git diff --check` pass. The generated resolver's
  category-override linker warning is expected. The accessor regression also
  logs refused retain/release attempts on a dead native receiver around context
  reset; these lifecycle diagnostics remain unresolved despite passing checks.

End-to-end: the accessor abort is gone. Under LC's original auto-selected SDK
2.0, a normal URL launch remains black; a bounded debugger sample finds the
main thread inside guest/native class initialization for `PHPublisherOpenRequest`.
A minimal double-initialization probe does **not** reproduce that wait, so no
speculative global initializer hook was added. With the actual original SDK
6.1, a normal URL launch displays the Nickelodeon splash/intro image, clipped
and rotated in the simulator. A native Foundation trap in
`_NSCallStackArray _descriptionWithBuffer:size:` was observed on debugger attach;
its underlying reason is not established. A subsequent clean, bounded debugger
launch did not catch an exception and again sampled the `PHPublisherOpenRequest`
initialization wait. The app also logs DNS failures for PlayHaven endpoints,
but those are not proven to cause the wait. This is **not yet a menu/playability
pass** or a confirmed device defect.

## Godzilla: still blocked by guest VM remapping

Fresh diagnostic launch reproduces:

```text
Unhandled Mach message id 3814
mach_msg -> _kernelrpc_vm_remap -> vm_remap -> game
```

The earlier missing `_kCMTimingInfoInvalid` and `AudioUnitAddPropertyListener`
blockers are already covered, but the game still requires guest VM remapping.
No fake-success or copy-in-place substitute was added for aliasing/COW behavior.
This agrees with the September 19 device finding, rather than establishing a
simulator-only failure. Godzilla remains unfixed.

## Other issue status and source exclusions

- [#52 SpongeBob Marbles](https://github.com/LiveContainer/LiveExec32/issues/52):
  the missing `AudioQueueReset` is covered by `f01b6cc` and the AudioQueue
  regressions; this pass does not claim an end-to-end game retest.
- [#55 Jumping Finn Turbo](https://github.com/LiveContainer/LiveExec32/issues/55)
  and [#54 Hero of Sparta / Hero of Sparta II](https://github.com/LiveContainer/LiveExec32/issues/54)
  were skipped because the issues supply separate, unapproved IPA links.
  The Hero of Sparta download in #52's comments is likewise excluded.
- The older unresolved queue remains in
  [the September 18 triage](issue-game-triage-2026-09-18.md) and
  [September 19 device report](device-game-compatibility-2026-09-19.md).
  Those games were not all re-evaluated in this pass.

Local, ignored diagnostic evidence and verified IPA files are under
`tmp/crash-followup-20260922/`; nothing was uploaded. Test debuggers were detached
and closed; the stalled simulator test app was stopped after recording evidence.
