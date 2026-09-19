# Air Hockey — OpenFeint controller cleanup crash

## Result

Fixed the missing ownership in synthetic guest object-ivar setters. Deployed
the rebuilt shared runtime to the existing simulator LC installation. Legacy
SDK (`131072`) and Classic Mode remain enabled. No game-specific hook, crash
suppression, or extra retirement-state check was added.

The real game's `RootControllerOf.nib` passed 10 consecutive load/teardown
cycles with both its controller and its view confirmed deallocated through
native weak references. The user also confirmed that the full played-round →
New Game interaction no longer crashes with the fixed build.

## Captured failure

- Air Hockey Gold 1.0.0, bundle `com.acceleroto.airhockeygold`.
- iPhone 17 Pro Max simulator, iOS 27.
- User reproduction stopped in `objc_release_x8`, `EXC_BAD_ACCESS` at
  `0x72c4abb24168`, on the main thread.
- Stack: `-[UIViewController dealloc]` →
  `LC32TransferredRootReference::releaseNow` →
  `LC32RetireGuestMirrorWithTransferredReference`.
- The retiring native controller was `OFRootController`. UIKit was releasing
  its `_view` (offset 24), whose allocation already contained a freed-object
  marker instead of a valid isa.

`RootControllerOf.nib` assigns the same UIView to the controller's native
`view` property and its bare guest `containerView` outlet. The guest
`-[OFRootController dealloc]` releases `containerView`, then calls super.
The synthetic outlet setter used `object_setInstanceVariable`, which does not
retain MRC ivars with unknown ownership. The outlet therefore never acquired
the reference it later released; UIKit subsequently released a freed view.

## Change

The synthetic object-ivar setter now calls the bundled guest runtime's
`object_setInstanceVariableWithStrongDefault`. This matches KVC direct-ivar
ownership for bare MRC outlets, balances replacement, and respects known ARC
strong/weak/unsafe-unretained layouts. Real guest setters remain unchanged.
The bridge helper was renamed to make this ownership policy explicit.

## Verification

- New `kvc-ivar-ownership` regression: **14/14 pass** with the fix. The saved
  baseline fails the three MRC ownership assertions. The baseline deliberately
  clears its unowned outlet before teardown to report failure without crashing.
- Covers inherited/literal-underscore outlets, self-assignment, replacement,
  nil assignment, class ivars, real assign setters, controller/view teardown,
  and ARC strong/weak/unsafe-unretained behavior. Native and guest autorelease
  pools are both drained for lifetime assertions.
- Existing regressions: pointer/out-parameters **14**, guest proxy lifetime
  **16**, ARC proxy lifetime **17**, native proxy release **23** PASS markers.
  All four guests exited with code 0.
- Real Air Hockey nib: **10/10** cycles. Each confirmed `OFRootController`,
  `containerView == view`, and zeroed weak controller/view references after
  the native autorelease pool drained. No skipped release or injected retain.
- User retest: completed one round and confirmed the subsequent New Game
  crash is fixed.
- Shared framework build and signature verification passed; `git diff --check`
  passed. Launcher remains LC-compatible `MH_DYLIB`.

Evidence and pre-fix runtime backup: `tmp/air-hockey-20260919/`.
Pre-fix shared-runtime SHA-256:
`c40a931ec64c4399658992fd9a85ceda7a4e3f4cc9a9380d14958089cc7e79a7`.
Deployed fixed shared-runtime SHA-256:
`4130be52b53a9ba30e07d6f3bf38f19858bf54150de092c03bfa679e0122350c`.

No Mac keyboard/mouse input was used. At handoff, LLDB was continued on PID
84972 with guest-crash and native-crash stops enabled. These process details
apply only to that debugging session. No changes were pushed.
