# Road Warrior 1.4.2 — forwarding crash diagnosis and fix

## Current status

**The Flurry forwarding crash is fixed locally; the game is not yet verified
playable.** After the fix, the simulator survives the original startup failure,
Flurry completes ad requests with ordinary network-failure callbacks, and the
guest keeps executing `glDrawArrays`. The screen remains black with repeated
Kamcord framebuffer/OpenGL errors. Treat that as a separate rendering follow-up,
not evidence that the forwarding fix failed or that rendering works on device.

No real-device retest, gameplay/touch test, or push in this pass.

## Implementation and validation

- Added a shared, bounded numeric-struct layout parser in
  `include/LC32PODType.h`. Guest full forwarding now counts struct argument
  words correctly, including the CGRect split between r3 and the caller stack.
- NSInvocation set/get argument and return-value storage marshals fields using
  each architecture's alignment; it does not memcpy native padding or pointers
  into guest buffers. Invalid setArgument storage/types now raise an exception,
  consistently with the existing get/set-return adapters.
- Added a signature-gated native callback adapter for mixed scalar/object/POD
  struct arguments. It captures both register banks, handles floating-point
  aggregates, indirect structs, and Apple's packed native stack arguments,
  then reconstructs the ARM32 call. It shares the scalar entry's assembly
  capture logic. There are no Flurry/Road Warrior selector exceptions or
  fabricated ad results.
- Supported structs are ordinary numeric fields, nested structs and fixed
  arrays, bounded to 32 leaf fields / 256 bytes / eight recursive levels.
  Opaque records, pointers/object fields, unions, bitfields and blocks are not
  newly supported. Aggregate-return **full forwarding** and aggregate callbacks
  on unregistered native threads remain unsupported; existing typed
  struct-return adapters are preserved. Struct set/getReturnValue storage is
  covered independently.
- `lc32-forwarding-structs`: **17/17** checks passed natively (with AddressSanitizer
  and UndefinedBehaviorSanitizer) and in the ARM32 simulator runtime. Covers the
  Flurry object/CGRect/int shape, selector retargeting, retained arguments,
  canaries, alignment/padding, nested arrays, register exhaustion, indirect
  aggregates, and signed narrow arguments. Before the fix, the same first
  forwarded call aborted with `unsupported argument encoding`.
- Existing `lc32-nsproxy-bridge`: **59/59** passed; `lc32-nsrange-bridge`:
  **12/12** passed; `lc32-guest-host-aggregate-arguments`: **7/7** passed,
  including native-to-guest CGFloat conversion and existing CGSize/CGRect
  return adapters; scalar signature scanner: **87/87** passed.
- Host and guest builds succeeded with `LC32_UIKIT_COMPATIBILITY=1`.

ABI handling follows [Apple's ARM64 calling-convention differences](https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms)
and the [AAPCS64 aggregate/HFA rules](https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst).
The ARM32 packing and native callback behavior are checked by compiled tests.

## Game retest

- Used an isolated runtime, `tmp/road-warrior-20260922/Runtime.app`, selected
  only for Road Warrior. Kept its existing Legacy SDK / Classic Mode settings:
  executable SDK 6.1 and LC's existing process override 2.0 (`131072`). SDK 11
  was not tested.
- A 50-second guest-debugger run no longer hit `LC32ForwardingFailure`; the
  timeout sample was in the rendering loop, not a fault. Logs show Flurry
  Code 117 ad-request failures returning to the game rather than aborting.
- Also relaunched through `livecontainer://livecontainer-launch`, without a
  debugger, to preserve the normal Classic Mode launch path. The process stayed
  alive but the captured screen remained black.
- Evidence: `tmp/road-warrior-20260922/fixed-guest-lldb.log`, `fixed.stdout`,
  `fixed.stderr`, `fixed-startup.png`, `fixed-url.png`, and the adjacent test
  logs. Only the scoped debug session was created; it detached and exited.
- Stopped the test app and restored Road Warrior's original runtime selection.
  The default LC runtime, SDK/Classic Mode settings and unrelated pending Core
  Data changes were not replaced. The existing user-owned shell debugger was
  left alone. No Mac keyboard/mouse automation was used.

## Original finding

Confirmed the first guest failure with an ARM32 LLDB breakpoint at
`LC32ForwardingFailure`, before it logs or aborts:

```text
receiver: FlurryAdsImpl
selector: fetchAdForSpace:frame:size:
reason: unsupported argument encoding
```

The embedded Flurry ad SDK deliberately forwards this message. Its method
signature, extracted from the game's Objective-C metadata, is:

```text
v32@0:4@8{CGRect={CGPoint=ff}{CGSize=ff}}12i28
```

This means **void return, object argument, CGRect argument, integer argument**.
The 16-byte ARM32 rectangle is the immediate unsupported value. This is an
emulator forwarding limitation, not evidence that Flurry's server response,
the simulator's rendering speed, or an orientation setting caused the abort.
The device has not been retested in this pass.

## Why the earlier trace was misleading

The guest stack includes `LC32GuestForwardMessageStret`, but both ordinary and
struct-return dispatchers share an assembly tail after that label. The label
alone does not establish a struct return. The observed failure reason comes
from the argument-encoding check; the method actually returns void.

The previous native `_NSCallStackArray _descriptionWithBuffer:size:` trap
occurred while formatting an uncaught exception. It is downstream of the guest
failure and is not the first problem to fix.

## Original bridge gaps

- `GuestFrameworks/Foundation/NSObject+LC32Forwarding.m`:
  `LC32ForwardingTypeWords` accepts scalar, object, class, and selector values,
  but rejects `{...}`. `LC32GuestForwardInvocation` consequently aborts before
  calling the game's `forwardInvocation:`.
- `HostFrameworks/LC32/bridge.mm`: the NSInvocation set/get value adapters also
  accept only scalar/object/selector types. Simply removing the guest rejection
  would encounter another unsupported conversion.
- The existing native-to-guest CGRect callback adapters cover a single CGRect
  argument, not this mixed object/CGRect/integer signature. The eventual invoke
  path needs ABI-correct handling too, including ARM32 register/stack splitting
  and native floating-point argument registers.

A proper fix needed coherent struct support across forwarding and
NSInvocation invocation, with a minimal regression matching this Flurry
signature. It should not silently discard the ad call, fake success, or add a
Road Warrior-specific selector exception. The original diagnostic pass made no
runtime changes; the implementation and retest are recorded above.

## Reproduction and evidence

- Existing verified LegacyStore copy `330218`, version **1.4.2**, bundle
  `com.mobjoy.3r`, executable `3r`, installed as `eval330218.app`.
- iPhone 17 Pro Max simulator, iOS 27; existing Classic Mode enabled. The game's
  executable declares SDK 6.1, and the runtime logs guest SDK 6.1.0. LC's existing
  process override remains its auto-selected SDK 2.0; no settings were changed.
- Used the user's existing default runtime, `com.kdt.LiveExec32.app`, not the
  separate Scribble Hero test runtime. No game binaries or data were replaced.
- First captured simulator stdout/stderr with native LLDB. Then used the guest
  debugger on **127.0.0.1:2347** and stopped at `LC32ForwardingFailure` before
  `fprintf`/`abort`. These are diagnostic launches, not viewport validation.
- Guest stack: forwarding failure → `LC32GuestForwardInvocation` → shared
  forwarding assembly → game `0xd7d9fc` (Flurry wrapper) → game `0x7f09e8`.
- Also observed Kamcord framebuffer errors and semaphore-wait diagnostics.
  These are not established as the cause of the captured forwarding abort.
- Evidence: `tmp/road-warrior-20260922/baseline-lldb.log` and
  `tmp/road-warrior-20260922/guest-lldb.log`; copied stdout/stderr alongside them.
- Both diagnostic LLDB sessions detached and exited. The test app was stopped.
  The user's pre-existing shell LLDB session was left untouched. No Mac input
  automation, source fixes, commits, or pushes were performed.
