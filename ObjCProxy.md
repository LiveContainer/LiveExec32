# Objective-C Proxy

## Design
The guest will have pre-generated host classes, while the host will dynamically register guest classes.
Each object, if referenced, stores the corresponding pointer of the other side of the world.
When calling objc_msgSend, it will convert all objc pointers to their corresponding pointers before passing them to the other side of the world.
Do note that guest has its own objc runtime which was borrowed from iOS 10 ramdisk 

### Guest world

### Host world

## Variadic methods

Objective-C method type encodings do not record whether a method has an
ellipsis. For example, `+[NSString stringWithFormat:]` has the same runtime
encoding as a fixed one-argument method, so generated shims need supplemental
metadata or a hand-written adapter.

The NSString format family uses such an adapter. It captures the original
ARMv7 `va_list` before making another call, sends it through SVC 1010, parses
the format on the host, and rebuilds the arguments as Darwin arm64 8-byte
variadic slots. This also converts guest objects and string pointers and
widens guest `long`, `size_t`, and `ptrdiff_t` values. The host then invokes the
exact selector with the correct fixed-prefix variadic prototype.

Currently supported adapters cover NSString construction, localized
formatting, appending, NSMutableString appending, and the explicit
`arguments:` initializers. Formats are capped at 64 arguments; `%n` and
malformed, mixed-position, conflicting-position, or holey formats fail closed.
Precision-bounded raw `%s`/`%S` buffers and strings-dictionary external/plural
specifiers also fail closed until their bounds or scalar metadata can be
translated without reading past guest memory.
Other variadic contracts (nil-terminated object lists, type-string-driven
arguments, and custom APIs) need separate adapter families.

### TODO
- Validate that overridden methods using category on guest works properly
- Extract public variadic metadata from SDK headers instead of growing a
  manual selector registry
