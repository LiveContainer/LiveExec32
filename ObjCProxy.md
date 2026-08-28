# Objective-C proxy bridge

LiveExec32 runs two independent Objective-C runtimes in one process:

- The **guest runtime** is the 32-bit Objective-C runtime from the iOS 10
  root filesystem. Guest objects, classes, selectors, pointers, `NSInteger`,
  and `CGFloat` follow the ARM32 ABI.
- The **host runtime** is the native ARM64 runtime used by the current Apple
  frameworks. Its object pointers and integer types are 64-bit, `CGFloat` is
  `double`, and aggregates follow AAPCS64 calling rules.

The bridge gives selected objects a peer in the other runtime and translates
method calls between those peers. A guest Objective-C pointer is never a
native Objective-C object; guest memory is accessed only through explicit
reads, writes, or staging. A host pointer must never be truncated and exposed
to the guest.

## Terminology

| Term | Meaning |
|---|---|
| Guest object | An Objective-C object at a 32-bit address in emulated memory. |
| Host object | A native Objective-C object at a 64-bit address. |
| Guest proxy | A guest object which represents a host object. |
| Host peer | The host object represented by a guest object. |
| Guest-backed host class | A native class synthesized for an app-defined guest class. Its installed IMPs call back into guest code. |
| Lifetime pin | One guest-only ownership reference held for the lifetime of a host peer. It is separate from the identity maps. |

`nil` is zero in both worlds. Only values identified by method metadata or a
manual bridge as `id`, `Class`, `SEL`, or another supported type are
translated. An arbitrary integer or C pointer is not implicitly treated as an
Objective-C object.

At a high level, the two call directions are:

```text
ARM32 app -> generated/manual guest shim -> SVC -> ARM64 objc_msgSend
ARM64 callback -> synthesized native IMP -> guest objc_msgSend -> ARM32 IMP
```

## Class model

There are two complementary class families.

### Native framework classes in the guest runtime

Framework classes available on the current host already exist in its native
runtime. LiveExec32 builds ARM32 guest implementations of selected iOS 10
interfaces. These generated methods do not implement the framework behavior;
they convert their arguments and forward to the corresponding native class.

The generation pipeline is:

1. Method metadata captured from the iOS 10 environment supplies the guest
   encodings. This preserves 32-bit pointer, integer, and `CGFloat` widths.
2. [GenerateShimAPI](Generator/GenerateShimAPI/main.m) validates the method
   encodings and emits guest forwarding methods.
3. [generate-shims.sh](GuestMakefile/generate-shims.sh) stages the result and
   atomically replaces `GuestFrameworks/.generated`.
4. Generated sources and hand-written framework adapters are compiled into
   the guest frameworks together.

A generated method normally caches the host selector, converts every
argument into the bridge representation, invokes the host, copies mutable
indirect arguments back, and converts the result according to the selector's
Objective-C ownership family. Methods with incomplete metadata or an
unsupported ABI are filtered and need a hand-written adapter.

### App-defined classes in the host runtime

Application classes are loaded normally by guest libobjc. When native
`objc_getClass` cannot find a class, the hook in
[bridge.mm](HostFrameworks/LC32/bridge.mm) checks
the guest runtime and, when appropriate:

1. resolves or synthesizes the superclass;
2. calls `objc_allocateClassPair`;
3. associates the guest class and metaclass addresses;
4. mirrors protocols, class methods, and instance methods;
5. installs selected KVC ivar accessors and UIKit compatibility methods;
6. installs coordinated native/guest lifetime hooks; and
7. registers and marks the class as guest-backed.

Guest ivars remain in the ARM32 object. They are not copied into the native
object layout. Synthetic KVC accessors retain class-specific bindings and
read or write the original guest memory.

Methods present during class registration are installed proactively. Dynamic
`+resolveClassMethod:` and `+resolveInstanceMethod:` can query guest libobjc
later, but only on a thread registered for guest execution. Native framework
threads cannot borrow another thread's guest JIT or stack.

The installed method starts with the guest encoding. For recognized
ABI-sensitive signatures, an inherited method or adopted native protocol can
supply an ARM64 encoding instead. Typed callback IMPs then handle the
supported float/double, `CGPoint`, `CGSize`, `CGRect`, `NSRange`, object-range,
and fast-enumeration differences. Other mirrored methods retain their guest
encoding.

### Super dispatch from guest overrides

If a guest override forwards the same selector to its host peer, ordinary
native dispatch would immediately enter the synthesized IMP and recurse back
into the guest. `LC32InvokeHostSelector` detects a guest-backed receiver,
walks past consecutive guest-backed host classes, and starts dispatch at the
first native superclass with typed `objc_msgSendSuper`.

The synthesized mirror's `release` is a deliberate exception because it must
coordinate native retirement with the guest lifetime pin. If a legacy
guest-only callback selector has no implementation in the modern native
superclass chain, the bridge logs it and treats it as a no-op.

## Object identity

Identity is asymmetric rather than a raw pointer stored directly in both
objects:

```text
guest u32 -- generation-checked native registry --> host id
guest u32 <-- kGuestSelf associated value -------- host id
guest +1  <-- native lifetime-pin association ---- host id
```

### Guest to host

Guest `-[NSObject host_self]` first asks the native registry for the existing
peer. If there is none, it serializes first publication, snapshots the guest
retain count, asks the host to create the peer, seeds the matching native
ownership, and only then publishes the mapping. Guest-only objects therefore
remain entirely local until they first cross the boundary.

The authoritative guest-to-host registry is native and weak. Its entry
contains the expected host address, a generation, a lifecycle state, and the
mapping lifetime. Keeping this outside guest associated-object storage avoids
re-entering guest libobjc association or weak tables while those tables may
already be locked.

Mappings can be provisional, lifetime-pinned, or permanent. Provisional
mappings allow an initializer to replace an allocation placeholder. Classes
and process-lifetime constants use permanent mappings. Live, retiring, and
superseded generations plus compare-before-clear teardown prevent a delayed
destructor from erasing a newer mapping after the same 32-bit address has been
reused.

### Host to guest

Host `-[NSObject guest_selfOrNull]` is lookup-only. `-guest_self` additionally
creates a proxy when needed: it finds the nearest available guest class,
allocates a raw guest instance, calls guest `-initWithHostSelf:`, records the
reverse association, and attaches a lifetime pin. Private native subclasses
may therefore be exposed through their nearest public guest superclass.

Class objects are peers too, but use permanent mappings. Native dispatch data
is intentionally exposed as guest `NSData`, whose manual byte-copy adapter
flattens the native object without relying on its private allocation layout.

Blocks bypass general NSObject peer creation, the guest-to-host registry, and
ordinary lifetime pins. The native wrapper still stores the reverse
`guest_self` association so it can recover its copied guest block, whose
ownership follows `_Block_copy`/`_Block_release` rules.

## Ownership and initialization

Identity and ownership are separate. The important result contracts are:

| Native contract | Bridge path | Guest result |
|---|---|---|
| Borrowed Objective-C `+0` | `LC32InvokeHostObjectSelector` | Reuses or creates the proxy without adding a guest retain/autorelease. |
| `alloc`/`new`/`copy`/`mutableCopy` or CF Create/Copy `+1` | `LC32HostToGuestOwnedObject` | Transfers the native `+1` and adds exactly one corresponding guest reference. |
| Initializer | `LC32AdoptHostInitializerResult` | Moves the allocated guest receiver's ownership to the canonical result proxy. |
| Block | Block bridge | Uses copied-block ownership, not NSObject retain/release pairing. |

A borrowed object is converted before the host invocation's SVC frame ends,
while the native autorelease-return lifetime is still valid. The host object
owns the proxy's initial guest lifetime pin, so manufacturing another guest
retain/autorelease would duplicate the native `+0` lifetime and can
over-release the host object later.

An owned result already carries a real native `+1`. The conversion adds the
guest half of that ownership without retaining the host again. If proxy
creation fails, the bridge consumes the native `+1`.

Initializers need a separate path because class clusters may return an object
different from the `+alloc` placeholder. The adoption helper binds the
explicit guest receiver to the returned native object, disposes a failed
initializer, and transfers ownership without double-retaining. ARC and MRC
entry points differ internally so generated method bodies can preserve their
respective compiler contracts.

Guest NSObject ownership methods are swizzled. Retaining or releasing a
mapped guest object updates both logical guest ownership and its paired native
ownership; operations on guest-only objects remain local. A stable ordinary
native peer holds one guest lifetime pin for its remaining lifetime, rather
than mirroring every native owner into the guest retain count. Provisional
allocation placeholders and permanent class/constant mappings follow their
own rules. If native destruction happens on an unregistered thread, final
guest-pin release is deferred until a registered guest thread can run it
safely.

Guest autorelease uses a native autorelease token. Weak retain is a two-phase,
host-first operation: the host obtains a native weak `+1`, guest libobjc tries
the weak retain, and a second SVC commits or rolls back the exact native
reference. This avoids doing recursive ownership work while guest libobjc's
weak table is locked.

## Guest-to-host method calls

The ordinary generated call sequence is:

```text
guest objc_msgSend
  -> generated guest method
  -> convert self and object arguments with host_self
  -> resolve/cache the native selector
  -> LC32InvokeHostSelector (SVC 1006)
  -> rebuild ARM64 arguments from native method metadata
  -> objc_msgSend or objc_msgSendSuper
  -> copy indirect arguments and convert the result
```

The SVC carries the native receiver, selector plus result flags, and up to
nine 8-byte logical argument slots. The host does not guess their types from
the bit patterns: it reads the native method encoding, validates any tagged
storage descriptors, separates integer and floating-point register banks,
and invokes a typed `objc_msgSend` shape.

The guest-side tagged argument protocol is defined in
[LC32ObjCBridgeABI.h](include/LC32ObjCBridgeABI.h). It covers:

- an ordinary eight-byte indirect cell;
- a canonical floating-point pointee which can widen `CGFloat *`;
- explicitly sized synchronous storage up to 64 bytes;
- counted object-pointer arrays;
- widened aggregates; and
- raw `NSInvocation` argument storage.

Tags are accepted only when the method encoding expects the corresponding
pointer or aggregate. This prevents a negative integer or floating-point bit
pattern from being mistaken for guest storage. Native temporary storage is
used for the call; only mutable indirect forms are copied back to the guest.

Scalar and floating results return through the SVC result words. Borrowed
object results use a selector flag so conversion happens inside the same
native return frame. Structure returns use explicit guest destination storage
and currently support `NSRange` plus the recognized 16-, 32-, and 48-byte
double-field layouts. Other layouts require a manual bridge.

## Host-to-guest method calls

A native send to a guest-backed class lands in an installed host IMP. The
generic trampoline consumes `x2` through `x7` and limited stack arguments
according to the native method encoding, converts objects and selectors,
narrows supported values into AAPCS32 words, and calls guest `objc_msgSend`.

`LC32InvokeGuestC` saves the outer guest CPU context, places the first four
guest words in `r0` through `r3`, writes the remaining words to an
eight-byte-aligned guest stack, places the target in `r12`, and runs the guest
callback trampoline. SVC 1009 marks its return boundary; `r0:r1` provide the
result, after which the outer guest context is restored. This supports nested
host-to-guest calls on the same registered thread.

The generic path handles at most eight encoded Objective-C arguments,
including `self` and `_cmd`. It cannot capture arbitrary ARM64 FP-register
arguments or every aggregate layout, so method installation selects typed
IMPs for the supported special signatures. A new signature that crosses an
ABI width or register-class boundary generally needs a typed trampoline, not
just a new type encoding.

## ABI marshalling rules

| Value family | Current treatment |
|---|---|
| Integer, enum, and boolean | Transported in 64-bit slots; generated code or typed adapters narrow and widen supported signatures. |
| `id` and `Class` | Converted with `host_self` or `guest_self`; never passed as raw cross-runtime pointers. |
| `SEL` | Resolved by selector name in the destination runtime. |
| `float`, `double`, and `CGFloat` | Repacked into the destination ABI's independent FP register bank; width is converted when required. |
| `NSRange` | Guest-to-host values widen from two 32-bit fields to two 64-bit fields; supported result and block paths narrow with `NSNotFound`/overflow checks. Reverse callbacks are signature-specific. |
| `CGPoint`, `CGSize`, `CGRect`, and known aggregates | Rebuilt for the native layout or handled by a typed reverse-call IMP. |
| Scalar pointer arguments | Staged in native temporary storage and copied back synchronously. |
| Counted `id *` arrays | Const input arrays are expanded into native 64-bit object-pointer arrays; output object buffers require manual adapters. |
| Pointer-returning APIs | Copy into guest memory or use `LC32GetAssociatedGuestBuffer`; never return a native pointer. |
| Unknown pointer or aggregate layouts | Rejected or filtered until a dedicated adapter exists. |

Method encodings describe logical types, not the entire calling convention.
They also do not guarantee that an iOS 10 declaration has the same widths as
the current host SDK. Both the captured guest encoding and the native runtime
encoding must be considered when adding bridge coverage.

## Private SVC transport

The guest veneers use `svc #0x80` with the bridge operation number in `r12`.
The main Objective-C-related operations are:

| Operation | Purpose |
|---:|---|
| 1001 | Resolve a native function or data symbol. |
| 1002 | Invoke a native C function returning 32 bits. |
| 1003–1004 | Expose and release a synchronous guest C-string view. |
| 1005 | Resolve a selector in the host runtime. |
| 1006 | Invoke a host Objective-C selector. |
| 1007 | Create or bind a native peer for a guest object or class. |
| 1008 | Copy a host class name into guest memory. |
| 1009 | Mark the return boundary of a reverse guest callback. |
| 1010 | Invoke the NSString variadic-format adapter. |
| 1011–1014 | Copy string/data values and perform range adapters. |
| 1015 | Wrap a copied guest block as a native block. |
| 1016 | Convert and transfer a native owned (`+1`) result. |
| 1017–1018 | Wait for and complete a serialized block callback. |
| 1019, 1021 | Begin and commit or roll back a cross-runtime weak retain. |
| 1020 | Copy a raw host C string safely into guest memory. |
| 1022–1023 | Look up or update the authoritative host mapping. |

The veneers live in [LC32.s](GuestFrameworks/LC32/LC32.s); the SVC cases are
serviced in
[dynarmic_callbacks.cpp](HostFrameworks/LC32/dynarmic_callbacks.cpp).

## Threading, reentrancy, and quiescence

Guest execution state is thread-local. An ordinary native-to-guest selector
call requires the current pthread to own a registered guest JIT and guest
stack; `LC32InvokeGuestC` logs and returns zero on an unregistered native
thread. Dynamic method resolution follows the same restriction.

An SVC that can enter native Objective-C first halts and unwinds the running
JIT. The outer run loop services it only after `Jit::Run()` has returned, so a
native method may synchronously call back into the guest without recursively
running an already-active JIT. Debugger quiescence brackets the actual native
`objc_msgSend`, while marshalling and copyout remain outside that interval. A
nested reverse callback temporarily revokes quiescence before it changes
guest registers and restores it after the guest context has been restored.

Foreign Foundation or GCD threads cannot borrow a guest execution context.
When native guest threading is active, the block bridge has a serialized
callback executor which submits a validated descriptor to a registered guest
thread and waits for completion. Ordinary Objective-C methods do not yet have
a general foreign-thread executor. Foreign-thread block releases normally use
the executor too; failed submissions fall back to deferred release. Deferred
lifetime-pin and fallback releases drain when a registered guest thread next
enters the bridge.

## Block bridge

`LC32CreateHostBlock` copies the guest block, validates its literal and
signature descriptor, and creates a native wrapper. The wrapper retains the
copied guest block until native destruction and uses guest `_Block_release`
for cleanup.

The current generic block ABI supports at most five logical arguments, eight
host ABI slots, and sixteen guest words. Results support void, object/class,
and selected signed or unsigned integer widths. Arguments additionally
support ARM32 `NSRange`/`CFRange` and selected one-byte pointer copy-in/out.
Floating point, arbitrary pointers, general aggregates, and pointer/range
results need dedicated adapters.

A host-created block cannot currently be synthesized as an arbitrary new
guest block result. The return path can reuse only a native wrapper already
mapped to its copied guest block.

## Why UIKit uses `LC32NativeView*`

The native view helpers in [UIKit.mm](HostFrameworks/UIKit/UIKit.mm) are
intentional dispatch-bypass calls. A cast to `UIView *` does not suppress
Objective-C dynamic dispatch: sending `setBounds:` to an instance of a
synthesized guest subclass could enter `LC32InvokeGuestSelector` and run ARM32
code from a native scene/layout callback, possibly on an unregistered thread.

The helpers cache the typed base `UIView` IMP and call it directly. This both
bypasses guest overrides and preserves the ARM64 `CGRect`/`CGPoint` calling
convention. Compatibility code may schedule the guest-visible layout work
later on a registered thread. `UIWindow` root-controller access uses a related
typed `objc_msgSendSuper` path which skips guest-backed classes while
preserving the first native implementation.

Do not replace these helpers with ordinary Objective-C messages unless the
call is explicitly intended to enter guest code and the current thread is
registered for guest execution.

## Variadic methods

Objective-C method type encodings do not record whether a method has an
ellipsis. For example, `+[NSString stringWithFormat:]` has the same runtime
encoding as a fixed one-argument method, so generated shims need supplemental
metadata or a hand-written adapter.

The NSString format family uses such an adapter. It captures the original
ARMv7 `va_list` before making another call, sends it through SVC 1010, parses
the format on the host, and rebuilds the arguments as Darwin ARM64 8-byte
variadic slots. This also converts guest objects and string pointers and
widens guest `long`, `size_t`, and `ptrdiff_t` values. The host then invokes the
exact selector with the correct fixed-prefix variadic prototype.

Currently supported adapters cover NSString construction, localized
formatting, appending, NSMutableString appending, and the explicit
`arguments:` initializers. Formats are capped at 64 arguments; `%n` and
malformed, mixed-position, conflicting-position, or holey formats fail
closed. Precision-bounded raw `%s`/`%S` buffers and strings-dictionary
external/plural specifiers also fail closed until their bounds or scalar
metadata can be translated without reading past guest memory.

A small selector allowlist also recognizes nil-terminated framework methods
such as the UIAppearance containment APIs. It places the explicit terminator
where Darwin ARM64 variadic code expects it on the stack; it does not make an
arbitrary variadic tail discoverable. Other contracts, including general
nil-terminated lists, type-string-driven arguments, and custom APIs, need
separate adapter families.

## Failure boundaries

- Do not cache or dereference a peer pointer in the wrong address space.
- Use `host_self` and `guest_self`; do not create an independent identity
  table or use peer-creation helpers as generic lookup functions.
- Use the owned-result conversion only when transferring a real native `+1`.
  Do not add a guest retain/autorelease around a borrowed result.
- Real ARM64 pointers are rejected by the generic reverse bridge. Only
  explicitly supported zero-extended opaque tokens may round-trip as
  `void *`; `NSZone *` is translated to null.
- Unsupported guest-to-host descriptors generally log and return zero.
  Several host-to-guest ABI violations abort rather than risk corrupting
  native or guest memory.
- Mirrored `.cxx_construct`, `.cxx_destruct`, and `dealloc` are deliberately
  not installed as generic host IMPs. Libobjc calls those hooks with special
  conventions, and guest C++ storage is already managed by guest libobjc.
- Runtime-generated compatibility shims based on the current host runtime
  need an explicit width audit. When an iOS 10 encoding exists, prefer it as
  the guest-facing source of truth.

## Diagnostics

The high-volume tracing switches are opt-in because they affect timing:

| Environment variable | Trace |
|---|---|
| `LC32_OBJC_TRACE=1` | Generated guest-to-host Objective-C sends. |
| `LC32_CALLBACK_TRACE=1` | Native-to-guest Objective-C callbacks. |
| `LC32_BLOCK_TRACE=1` | Block creation, invocation, executor, and release paths. |
| `LC32_OPERATION_TRACE=1` | NSOperation proxy identity and ownership transitions. |
| `LC32_NETWORK_TRACE=1` | Selected network-object crossings. |

## Implementation map

- [bridge.mm](HostFrameworks/LC32/bridge.mm): identity registry, object
  conversion, native class
  synthesis, selector marshalling, lifetime pins, and weak ownership.
- [LC32.h](GuestFrameworks/LC32/LC32.h),
  [LC32.m](GuestFrameworks/LC32/LC32.m), and
  [LC32.s](GuestFrameworks/LC32/LC32.s): guest-facing proxy APIs, ownership
  swizzles, tagged argument helpers, and SVC veneers.
- [LC32ObjCBridgeABI.h](include/LC32ObjCBridgeABI.h): shared selector flags,
  pointer tags, mapping operations, and descriptor layouts.
- [GenerateShimAPI](Generator/GenerateShimAPI/main.m): generated framework
  method bodies and ownership-family selection.
- [block_bridge.mm](HostFrameworks/LC32/block_bridge.mm) and
  [LC32BlockBridgeABI.h](include/LC32BlockBridgeABI.h): block signature
  translation and foreign-thread callback execution.
- [UIKit.mm](HostFrameworks/UIKit/UIKit.mm): UIKit-specific guest class
  preparation and native-only compatibility dispatch.
- [dynarmic_callbacks.cpp](HostFrameworks/LC32/dynarmic_callbacks.cpp),
  [dynarmic_core.cpp](HostFrameworks/LC32/dynarmic_core.cpp), and
  [dynarmic_thread_state.cpp](HostFrameworks/LC32/dynarmic_thread_state.cpp):
  SVC servicing, nested execution, and debugger
  quiescence.

## TODO

- Validate category overrides added after guest class registration, including
  method replacement and cache invalidation behavior.
- Extract public variadic metadata from SDK headers instead of growing a
  manual selector registry.
- Add a general policy for ordinary Objective-C callbacks arriving on foreign
  native threads.
- Replace remaining selector-specific ABI trampolines with validated,
  reusable signature descriptions where practical.
