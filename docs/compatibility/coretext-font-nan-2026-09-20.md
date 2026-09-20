# CoreText NaN font metrics — live Simulator LLDB trace

## Result

Reproduced the native Footnote font failure on iOS 26.0 (23A343), with a
real SDK-7 Mach-O executable and Vietnamese process language preferences.
LLDB confirmed that finite font metrics are overwritten with NaNs by
CoreText's language-aware line adjustment. No LiveExec32 runtime or
compatibility hooks are linked into the probe.

This explains the chain observed in Air Hockey Gold on the physical device:
`CTFontGetAscent` / `CTFontGetDescent` return NaN, UIFont caches invalid
ascender/line-height values, `_bodyLeading` becomes NaN, and
`_scaledValueForValue:useLanguageAwareScaling:` caches a NaN Footnote baseline.
The alert margin derived from that baseline is rejected by NSLayoutConstraint.
The live trace here is of an isolated native probe, not the game process.

No production fix was changed during this investigation. The device debugger,
installed games, global language settings, and Mac keyboard/mouse were untouched.

## Reproduction and controls

The probe requests `UIFontTextStyleFootnote` with
`UIContentSizeCategoryLarge`, then reads CoreText metrics, UIFont line height,
and both language-aware and non-language-aware scaling of the value 27.
It runs before any `UIApplicationMain` call or window creation.

The same ARM64 Simulator executable was built against the current SDK and
given SDK-7 or SDK-11 `LC_BUILD_VERSION` metadata with `vtool`; minimum OS
remained 15.0. Languages/locales were passed only as process launch arguments.

| Runtime | Declared SDK | Language | Size | Ascent | Descent | Line height | Scaled 27, unaware / aware |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| iOS 26.0 | 7 | vi | 13 | NaN | NaN | NaN | NaN / NaN |
| iOS 26.0 | 7 | en | 13 | 12.3779 | 3.13574 | 15.5137 | 27 / 27 |
| iOS 26.0 | 11 | vi | 13 | 13.2379 | 4.27581 | 17.5137 | 27 / 30 |
| iOS 27.0 | 7 | vi | 13 | 13.0524 | 4.21592 | 17.2684 | 27 / 29.632 |

All four report 2048 units/em and finite leading of 2.48633. The iOS-27
result is limited to this Footnote/Large case; it does not establish that
all styles or accessibility categories are fixed.

## Live trace: where the NaN originates

### 1. FindTextStyle incompletely fills the legacy override

The iOS-26 CoreText UUID is `02DCAAEC-4B66-366F-AAD5-8CCBDAE58570`.
All file addresses below apply only to that binary. LLDB's
`breakpoint set -s CoreText -a ADDRESS` resolves its load slide.

At `FindTextStyle +540`, file address `0x91574`:

- `x20` points to the real table record, style ID `0x52`, used for Footnote.
- `x19` points to the temporary legacy override record.
- The real record's language tail at `+0x138` contains `40, 42, 46`.
- The override's corresponding tail already contains three NaNs.
- The real first accessibility record at `+0xc0` contains `46, 58, 0`;
  the override's corresponding fields are NaN.

The following copy transfers only `0xa8` bytes, beginning at `+0x18`:
seven normal-category records. The subsequent loop copies the still-NaN
first accessibility record to the five accessibility slots. It does not
populate the language tail.

At `FindTextStyle +596`, file address `0x915ac`, after that work:

```text
override +0x60:  26, 36       (normal Large size and line height)
override +0xc0:  NaN, NaN, NaN
override +0x138: NaN, NaN, NaN
```

Thus the font has a valid normal point size (26 / 2 = 13), but the selected
legacy override loses finite language metrics that exist in the real table.

### 2. Vietnamese selects the unfilled language field

In a separate fresh run, LLDB stopped in
`LanguageAwareLineSpacingOverrideRatio`:

- At `+112`, `w0 == 2`: the preferred-language selection chose group 2.
- The selected offset is `0x128 + 2 * 8 == 0x138`.
- The three tail doubles contain the exact bits `0xffffffffffffffff`.
- At `+132`, immediately before `fdiv`, `d0 == NaN` and `d1 == 36`.

The preceding zero check does not reject NaN. The division therefore
propagates a placeholder NaN; it is not division by a zero line height.
The captured caller was `MakeSpliceDescriptor` during native font creation.

### 3. AdjustLineMetrics overwrites valid ascent and descent

In a fresh LLDB run, the stack was:

```text
CTFontGetAscent
  TFont::InitStrikeMetrics
    TFont::GetStrikeMetrics
      TBaseFont::GetStrikeMetrics
        TBaseFont::InitFontMetrics
          TComponentFont::GetStrikeMetricsForSystemFont
            TComponentFont::AdjustLineMetrics
```

At `AdjustLineMetrics +240`, file address `0x10a724`:

```text
d8 (language-aware ratio): NaN
StrikeMetrics units/em:   2048
StrikeMetrics ascent:     1950
StrikeMetrics descent:    494
StrikeMetrics leading:    0
```

The `fcmp d8, #0` / `b.ls` check does not take the early-return branch for
unordered NaN. The function continues through its language-aware arithmetic.

At `+660`, file address `0x10a8c8`, immediately before
`stp d1, d0, [x19, #8]`:

```text
d1 (new ascent):  NaN
d0 (new descent): NaN
old memory:      1950, 494
```

After stepping that single instruction, memory at the same ascent/descent
slots reads `NaN, NaN`. The getters subsequently return the corrupt cached
metrics. This directly identifies the write, rather than inferring the
cause from the final UIKit exception.

## Implications

- The initial empty UIFont scaling dictionary is normal lazy initialization.
  It later caches a bad value produced upstream.
- This reproduction is not an ARM32/ARM64 forwarding error, missing font file,
  or corruption of the font's original ascent/descent data.
- Returning the input when `_scaledValueForValue:useLanguageAwareScaling:`
  returns nonfinite would contain that layout calculation, but leaves the
  underlying UIFont/CoreText metrics invalid for other consumers.
- An upstream repair must avoid using the incomplete legacy language metrics
  or repair the font before invalid metrics are cached. No new hook or binary
  patch was implemented here.
- A fresh process is important: CoreText metrics and UIFont scaling baselines
  are cached, so late changes need not repair objects already created.

## Artifacts and cleanup

Local diagnostic files are preserved under
`/private/tmp/lc32-font-nan-lldb.JI1lBz/`:

- `FontNaNProbe.m`, `Info.plist`, `build.sh`, and the SDK-7/11 probe bundles.
- `ios26-lldb.log`: language-group and NaN/36 captures. LLDB itself crashed
  during subsequent stepping; this was a debugger crash, not the font probe.
- `ios26-lldb-complete.log`: fresh-session table-copy and finite-to-NaN write
  captures, with the probe subsequently exiting successfully.
- `ios26-sdk7-vi.log`, `ios26-sdk7-en.log`, `ios26-sdk11-vi.log`, and
  `ios27-sdk7-vi.log`: independent native comparison runs.
- `find-style.asm` and `adjust-metrics.asm`: disassembly of the tested iOS-26
  functions.

The temporary probe bundle IDs are
`org.liveexec32.test.fontnan.ji1lbz.sdk7` and
`org.liveexec32.test.fontnan.ji1lbz.sdk11`. Both probe apps were removed from
both simulators. The iOS-26 simulator that this investigation booted was
returned to its original shutdown state; the originally booted iOS-27
simulator remains running. The local probe bundles and logs remain available.
