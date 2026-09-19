# Real-device game compatibility — 19 September 2026

## Result

Implemented and deployed shared compatibility fixes for the ten reported
startup failures. All ten games were launched again on the phone, and each
progressed beyond its originally reported failure. **This is not an all-games
pass:** several now expose a second failure, and full gameplay was not tested.

Candy Crush reaches its startup interface, Pou reaches its Kitchen interface
and permission prompts, and FIFA 14 now reaches its EA terms dialog. My Little
Pony plays its intro but subsequently hits a backgrounding watchdog. The other
remaining problems are recorded below rather than hidden by crash suppression.

## Environment and scope

- iPhone 15 Pro Max (`iPhone16,2`), iOS 26.1 development build.
- Wi-Fi only: existing native device tunnel using pymobiledevice3 11.12.5 from
  `/Users/duy/.venv/`, plus SSH as `mobile`/`root` to
  `iphone-0xf-26-cua-duy.local`. No venv updates were necessary.
- These are the phone's existing standalone/injected game installations, not
  simulator LC bundles. Existing game SDK/configuration values were preserved;
  this was not an SDK-mode comparison.
- No Mac keyboard/mouse input, USB connection, replacement game binary, save
  edit, account login, or EULA acceptance. The user dismissed the system
  local-network prompt; the agent did not choose a permission setting.
- Only the shared runtime and five guest framework binaries were installed.
  No launcher or game bundle was changed. No app-name-specific hooks were added.

## Per-game retest

| Game | Original failure addressed | Observed result / remaining work |
| --- | --- | --- |
| Asphalt 4 | Missing `-[MPMoviePlayerController setBackgroundColor:]` | Stayed running for roughly two minutes without that exception, but displayed a black screen. Not playable in this test. |
| Crazy Squares 2.0.3 | Unhandled Mach message `3614` | Passes the thread exception-port probe, then faults reading guest address `0x117c31f8`, PC `0x00134fbc` in stripped game code. Still crashes. |
| Candy Crush 1.05 | Missing `_CGColorSpaceGetNumberOfComponents` | Displayed the Facebook Connect / Miss out startup interface; remained alive for about 48 seconds. No login or gameplay attempted. |
| FIFA 14 | Missing `_NewAUGraph` | Also uncovered and fixed nil `NSPort` creation, then ioctl `0xc0644e03` during DNS address sorting. Final launch remained alive beyond 80 seconds and reached the upright, correctly rendered EA terms dialog. Left at that dialog; gameplay not tested. |
| Godzilla Strike Zone 1.1.0 | Missing `_kCMTimingInfoInvalid` | Also uncovered and added `_AudioUnitAddPropertyListener`. Now aborts on Mach message `3814` (`vm_remap`). Requires a real guest VM remapping implementation, not fake success. |
| My Little Pony 1.0.0 | Missing `setUseApplicationAudioSession:` | Intro movie visibly played in landscape. Switching away later caused a 10-second scene-update watchdog termination (`0x8BADF00D`). Background lifecycle remains broken. |
| Peggle Classic 1.7.2 | Nil port passed to `NSRunLoop addPort:forMode:` | Also fixed the abort on Mach `3403` in libxpc's pre-fork probe. Final launch remained running, but content was badly clipped/rotated. Rendering still needs work. |
| Pou 1.1.26 | Missing `_CGColorRetain` | Also exposed `_CGPathAddEllipseInRect` and `_CGColorCreateCopy`; added those and audited the remaining CoreGraphics imports. Final launch reached Kitchen and notification permission UI and survived over 55 seconds. Partly black rendering and gameplay are not cleared. |
| Tetris | Unsupported NSString format `%@/%Info.plist`; missing `_NewAUGraph` | Both startup aborts cleared. Initially showed a navy canvas with a white block. On backgrounding, aborted in `LC32GuestForwardInvocation` / `LC32GuestForwardMessageStret`. Rendering and background lifecycle remain broken. |
| Zombie Tsunami 1.6.2 | Unhandled Darwin trap `-14` | Guest VM protection call now completes. Next abort is in Crittercism's `-[CRNetworkMonitor swizzleDelegates]`: `cannot forward guest +[UICommand host_self]: no method-signature provider`. Still crashes. |

The early observation that FIFA merely remained on its splash was incomplete:
its later reports identified the DNS ioctl abort. The final retest above is
after that additional fix. Similarly, My Little Pony and Tetris are not marked
successful merely because they survived their initial observation windows.

## Implementation

- **CoreGraphics:** `CGColorRetain`, immutable `CGColorCreateCopy`, color-space
  component counts, ellipse and quadratic path segments, and context alpha.
  Geometry and float values use the existing typed bridge operations.
- **CoreMedia:** exported `kCMTimingInfoInvalid` with three invalid `CMTime`
  values and the ARM32 `CMSampleTimingInfo` layout.
- **MediaPlayer:** legacy background color forwards to `backgroundView`;
  `useApplicationAudioSession` stores the legacy preference (default YES).
  The modern shared audio-session behavior remains unchanged: setting NO does
  not create an isolated historical movie-player audio session.
- **AudioToolbox:** guest-owned AUGraph nodes/connections/lifecycle reuse the
  existing AudioUnit adapters. Only supported components are accepted; this is
  not a complete implementation of every AUGraph API/component. Guest callback
  pointers never go to native AUGraph. Added property listeners with snapshots
  taken under the unit lock and callbacks invoked outside it, including running
  state changes on start, stop, and uninitialization.
- **Foundation ports:** native `NSMachPort` is weak-unavailable. A normal,
  weak-compatible `NSPort` peer now owns the real native port and forwards its
  operations. The bridge's weak receiver leases/dead-object checks are retained;
  no global lifetime bypass or process-lifetime retain was introduced.
- **NSString:** preserve the native non-consuming `%I` format behavior,
  including the reported path expression. No exact-path/game-name check.
- **Mach:** thread exception-port probes get a real unsupported reply, matching
  existing task-exception behavior. ARM32 reporters must not become handlers
  for the emulator host's ARM64 exceptions. `mach_ports_register` also reports
  unsupported instead of replacing host-task ports; fork remains rejected.
- **VM trap `-14`:** decode the ARM32 `wllww` argument layout and apply current
  protections to guest mappings with JIT invalidation. Unsupported maximum
  protection changes are not falsely reported as successful.
- **Kernel-control ioctl:** stage the fixed 100-byte `ctl_info` payload in host
  memory, preserve native errors, then copy the result back. Uses the same
  bounded copy helper as the existing pointer-free interface-query ioctls.
  This is the name-to-control-ID lookup described by
  [Apple's `ctl_info` documentation](https://developer.apple.com/documentation/kernel/ctl_info)
  and [XNU's ABI declarations](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/kern_control.h).

## Verification and limits

- Final ARM64 shared-framework build and ARM32 guest-framework build: pass.
- Final host regressions: **119 PASS**, no failures: movie-player compatibility
  66, Mach exception messages 18, weak-compatible port peer 8, CoreMedia 27.
- Initial on-device ARM32 regression batch: CoreGraphics 27, CoreMedia 27,
  MediaPlayer 5, NSString formatting, Mach RPC 51, and VM protection 11 all
  completed with guest exit code 0.
- The initial AUGraph device run passed through graph start (17 assertions),
  then hit an unoptimized ARM32 atomic fetch-add instruction in the test's
  counter. The test now uses an atomic flag. **No complete post-change device
  pass is claimed** for AUGraph/property listeners.
- Later standalone guest regression launches were terminated before their
  assertions by native `EXC_GUARD / REQUIRE_REPLY_PORT_SEMANTICS`, including
  the dedicated ioctl test. An app-context launcher attempt separately failed
  its native log-file-opening assertion. Neither security restrictions nor
  assertions were disabled to force a pass. This test-launch issue remains open.
- The latest guest tests compile, but new port-factory, property-listener,
  additional graphics, Mach-3403, and ioctl assertions do not have a complete
  post-change ARM32 device run. Actual games exercise the paths as described
  in the table; that does not substitute for complete regression coverage.
- Native port-peer regression on the phone: **8/8 pass**. Native kernel-control
  reference regression: **8/8 pass** on both phone and Mac; it only looks up a
  control ID and does not create/connect a network interface.
- Latest CoreGraphics native-reference regression: **31/31 pass**. This validates
  expected assertions against Apple's implementation, not the entire guest
  implementation. CoreGraphics export audit and `git diff --check`: pass.
- No gameplay, audio listening, touch, or full resume-cycle pass is claimed.
  Slow/incorrect rendering in this report occurred on the real phone, so it is
  not classified as simulator-only behavior.

## Evidence and installed state

Local, ignored evidence directory: `tmp/device-games-20260919/`.
It contains focused build/test logs and these crash reports:

- `crazy-candidate.ips`, `fifa-candidate.ips`, `fifa-ports-late.ips`
- `godzilla-candidate.ips`, `godzilla-listener.ips`, `peggle-ports.ips`
- `pou-candidate.ips`, `pou-ellipse.ips`, `zombie-candidate.ips`
- `pony-late.ips`, `tetris-late.ips`, `kernel-control-cli.ips`

Selected screenshots are saved beside the logs, including
`lc32-fifa-final.png`, `lc32-candy-candidate.png`, `lc32-pony-candidate.png`,
`lc32-peggle-fork.png`, and `lc32-pou-final.png`.

Original runtime backup on the phone:
`/var/mobile/Media/lc32-runtime-before.Kq3Z0d`.
It contains the shared framework executable and the original Foundation,
CoreGraphics, CoreMedia, MediaPlayer, and AudioToolbox executables. The backup
was not overwritten. Installed files were replaced via staged sibling files,
not by truncating a mapped library.

Final installed SHA-256 values (`final-device-status.log`):

| Binary | SHA-256 |
| --- | --- |
| LiveExec32Shared | `26ea035801b2b088fb0ea8d9ba89961fff9c1b686d3422cd4b794557cae3aa64` |
| Foundation | `753a676806d6ca74b60cf4b021431c3eae2259bcc211e60bcaeb6f4631573380` |
| CoreGraphics | `64f4e228b90299d22751c76ae224a78217379ace090f8fc1ca09f93b8766a133` |
| CoreMedia | `4e761a4fbd2882d06a921a47c23dc30aa2aa8e29e9bda5509400ad5e97ac0715` |
| MediaPlayer | `6ef5b2a7a120359b7ef995d878b07fd384482118f11844239b4dc9d27f65306b` |
| AudioToolbox | `bb2c3d9efdadf814058768b1d286cb447151637fae55dfb1b8a2e0708b730979` |

At handoff, FIFA is left at its terms dialog. No debugger is attached or leaving
a game paused. The test session's other live game processes and stale DVT
output streams were stopped. Changes are committed locally; nothing was pushed.
