# Configuration and diagnostics

[Back to the README](../README.md) · [Build instructions](building.md)

Build commands below run from the repository root.

## Debug logging

Verbose host bridge, loader, memory, syscall, and thread logs are compiled
out by default. Build with `gmake LC32_DEBUG_LOGS=1` to enable them; rebuild
with `gmake LC32_DEBUG_LOGS=0` (or plain `gmake`) to disable them again.
Errors and actionable warnings remain enabled in both modes. Guest
Objective-C tracing has its own build flag described below; other
specialized runtime trace controls are unchanged.

### Guest Objective-C tracing

Generated Objective-C send tracing is a guest build-time option, disabled
by default. Enable it with `gmake -C GuestMakefile LC32_OBJC_TRACE=1`;
rebuild with `LC32_OBJC_TRACE=0` to disable it. Runtime environment variables
do not configure this tracing, including an explicitly forwarded
`LC32_GUEST_ENV_LC32_OBJC_TRACE` value.
Repack the guest root filesystem and rebuild the app to deploy the changed
guest frameworks.

For the specialized callback, block, operation, and network trace controls,
see [proxy bridge diagnostics](ObjCProxy.md#diagnostics).

## Guest environment

Host environment variables are isolated from the guest by default. To pass a
specific value, prefix its name with `LC32_GUEST_ENV_`; the launcher strips
that prefix when constructing the guest environment. For example:

```bash
LC32_GUEST_ENV_NSUnbufferedIO=YES \
/path/to/LiveExec32.app/LiveExec32 /var/mobile/ramdisk32/usr/bin/fdisk
```

`HOME`, `NATIVE_GUEST_THREADS`, and `DYLD_SHARED_REGION` remain
launcher-owned and cannot be overridden through
this mechanism. `DYLD_PRINT_*` diagnostics are disabled by default, but can
be enabled explicitly, for example with
`LC32_GUEST_ENV_DYLD_PRINT_SEGMENTS=1`.

## SDK and UIKit compatibility

### Jailbreak injection and legacy bundle paths

The jailbreak injector preserves the ARM32 app's original SDK in the
arm64 shim by default (`LC32_PRESERVE_GUEST_SDK=1`), including missing/zero
SDK values. To opt out and floor the reported SDK at iOS 11, build the deb
with `gmake PACKAGE_FORMAT=deb LC32_PRESERVE_GUEST_SDK=0 package` (plus
your usual package-scheme/install options). The shim's minimum OS remains
iOS 11 in either mode. This affects newly injected executables; it does not
rewrite apps that already contain an arm64 shim, or change LiveContainer's
SDK override. Rebuild without this flag to restore preservation for
subsequent injections.
Pre-iOS-8 guests still get their legacy `HOME/LiveExec32.app` bundle alias
in LiveContainer, independently of UIKit compatibility mode. Its target
is relative to the selected guest container, so relocating LiveContainer's
outer container keeps it valid. Matching older absolute aliases are upgraded;
unrelated entries and the standalone installer's two-link layout are preserved.

### Low-SDK layout, rotation, fonts, and alerts

Low-SDK execution remains experimental. The host supplies narrow UIKit
layout-policy compatibility for layout guides, text-effects and keyboard windows
without raising the process SDK. An opt-in native Simulator regression is
available with `sh test/uikit_legacy_sdk_layout.sh --device UDID --baseline`;
it tests actual SDK 0, 7, 8, 10.3, and 11 Mach-O variants, needs an already
booted Simulator, and installs/removes only its own temporary test apps.
Processes with an effective SDK before iOS 8 use UIKit's native legacy
rotation and geometry instead of LiveExec32's adapters, avoiding a duplicate
turn. This follows dyld's process-SDK query, including LiveContainer's SDK
override installed before LiveExec32 loads. Thus an unclamped old SDK in
LiveContainer disables these adapters, while existing SDK-11-clamped
executables or LiveContainer overrides retain them. The native test also
includes policy-only cases with an SDK-11 executable and test-provided
effective SDKs; those isolate this selection without spoofing UIKit itself.
To compare native UIKit geometry on
newer hosts, launch with `LC32_DISABLE_UIKIT_COMPATIBILITY=1` in the host
process environment. This disables the host and guest canvas, orientation,
and synthetic-root adaptations, but retains the low-SDK Auto Layout fixes,
missing-API wrappers, and bridge recursion protection. The setting is read
once at launch; restart without it to restore the SDK-based default.
Pre-iOS-11 processes also repair nonfinite preferred-font results from
CoreText's legacy text-style tables (including Vietnamese line metrics).
Valid fonts are unchanged. Broken results use their resolved native face
and a concrete descriptor; missing accessibility sizes fall back to the
largest normal legacy category, not the modern accessibility-size table.
This repair stays enabled when geometry compatibility is disabled and
does not change the process SDK or language preferences. Run the native
font regression with `sh test/uikit_legacy_font_metrics.sh --device UDID`.
In processes reporting an SDK before iOS 8, native alerts also use matched modern presentation,
layout and animator paths so action sheets do not collapse or remove their
presenting view. The policy overrides are limited to the native methods
handling an alert; ordinary window rotation retains the original SDK's
behavior. These hooks install together only when the required native
methods are available. The font regression also checks text-field alerts,
titled/untitled action sheets, repeated animated/nonanimated dismissal,
presenter visibility and preservation of the native window policy.

## Build troubleshooting

For a missing classic linker or incorrect ARM32 Thumb initializer pointers,
see [ARM32 linker selection](building.md#arm32-linker). For SDK download,
checksum, and mirror overrides, see [guest SDK setup](building.md#guest-sdk).
