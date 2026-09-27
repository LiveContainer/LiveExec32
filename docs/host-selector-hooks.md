# Guest-to-host selector hooks

Framework policy belongs beside its framework, not in
`LC32InvokeHostSelector`. `HostFrameworks/LC32/host_selector_hooks.h` provides
class-scoped hooks for calls crossing that bridge. This is deliberately not a
process-wide swizzle: Foundation/UIKit's native calls retain their public
methods, buffers, and selectors.

## Dispatch

1. The bridge acquires the receiver and resolves its native dispatch class,
   skipping mirrored guest classes as before.
2. It looks up the original selector's nearest registered class hook. Unrelated
   classes with the same selector are unaffected. Registration/lookup is
   synchronized; framework code never runs under the registry lock.
3. An optional replacement selector is dispatched through the normal bridge,
   using its own native method encoding. Receiver lifetime, guest-thread
   quiescence, argument conversion, and result ownership remain centralized.
4. An optional `didInvoke` callback runs after a successful native call, at the
   former post-call boundary. UIKit's own nested native setters do not trigger
   it, and native subclass overrides finish before it runs.

Adapters which delegate to the original native method use
`LC32NativeHostMethod(receiver, originalSelector)` and pass the original `_cmd`.
This preserves native subclass overrides without recursively calling a mirrored
guest override.

## Framework ownership

- `HostFrameworks/Foundation/NSInvocation.mm`: selector conversion and typed
  argument/return storage. Private entry points transport guest addresses as
  `uint32_t`, not native pointers. Struct fields retain the existing ARM32/native
  layout conversion. The invocation pointer tag is retired; its value is not
  reused. Host and guest products should be deployed together.
- `HostFrameworks/Foundation/ObjectCallbacks.mm`: the legacy misdeclared
  notification and cross-thread `performSelector:…withObject:` callback adapter.
  The generic bridge retains the shared
  synchronous `void(id)` guest callback executor, including foreign threads.
- `HostFrameworks/UIKit/GuestSelectorHooks.mm`: optional-nib behavior, the
  per-receiver recursive `view` guard, and post-call UIView geometry,
  `addSubview:`, and autoresizing notifications.
- UIView mutation-hook registrations are compiled out with
  `LC32_UIKIT_COMPATIBILITY=0`. Essential view loading and nib forwarding remain;
  the existing nib helper controls its compatibility exception policy.

Retain/release/retainCount handling remains in the dispatcher because it depends
on that call's receiver-ownership guard. Generic ABI conversion, native-super
dispatch and variadic calling conventions also remain there.

## Regression checks

- `gmake -C test check-host-selector-hooks`: lookup scoping/inheritance,
  native-subclass dispatch, untouched native methods, and concurrent access.
- `gmake -C test check-uikit-compatibility-switch`: both compile modes, including
  optional mutation registrations and retained view/nib adapters.
- ARM32 simulator: `lc32-forwarding-structs`, `lc32-nsproxy-bridge`,
  `lc32-notification-selector`, `lc32-guest-host-aggregate-arguments`,
  `lc32-uikit-nib-awakening`, and `lc32-uikit-view-load-reentrancy`.
- `test/nsinvocation_native_buffers.m`, compiled for the native ARM64 simulator
  and linked against the simulator `LiveExec32Shared` framework, verifies that
  real hook registrations leave native selectors, objects and 64-bit range
  buffers unchanged. It also asserts that the real adapters were loaded.
- The SDK-7 `lc32-uikit-legacy-root-geometry` application fixture checks the
  deferred geometry callbacks in a live scene, not just command-line UIKit.

2026-09-22 validation: 10 registry, 8 native invocation, 17 struct forwarding,
59 NSProxy, 27 notification, 7 aggregate, 3 nib-awakening, 2 view-loading,
10 scene-geometry and 6 nib-policy checks passed. Both UIKit compile modes passed.
Logs are under `tmp/selector-hooks-20260922/` (ignored local artifacts).
