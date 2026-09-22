# AudioQueue missing APIs — September 21, 2026

## Reported failure

[Issue #52](https://github.com/LiveContainer/LiveExec32/issues/52) reports
SpongeBob Marbles 2.5 (`com.mtvn.SpongeBobMarblesSlides`) crashing when menu music
loops or when Start is selected. Its attached crash report identifies the
missing `_AudioQueueReset` symbol, called by `SoundQueue::play` on the game's
sound thread.

This change addresses that missing symbol and audits the neighboring public
AudioQueue C API against the iOS 10.3 SDK. It does not claim an end-to-end
SpongeBob gameplay retest or complete AudioToolbox coverage.

## Implemented

New guest exports, forwarded to the native queue through the existing token
and lifecycle bridge:

- `AudioQueueReset`
- `AudioQueueGetParameter`
- `AudioQueueGetPropertySize`
- `AudioQueueDeviceTranslateTime`
- `AudioQueueDeviceGetNearestStartTime`

Previously stubbed/partial functions now forwarded to native AudioToolbox:

- `AudioQueueFlush` (previously reported success without flushing)
- `AudioQueueEnqueueBufferWithParameters` (trimming, parameter events, optional
  start time and actual-start timestamp)
- `AudioQueueSetOfflineRenderFormat`
- `AudioQueueOfflineRender` (copies rendered audio and buffer sizes back to the
  ARM32 buffer without exposing native pointers)

New opcodes are appended, preserving existing numbering. The parameter-event,
timestamp and channel-layout ABI is checked explicitly; variable-length input
is bounded. Property-size queries use the same pointer-free property allowlist
as the existing get/set bridge.

Reset uses the ordinary buffer-return callback bridge, including native
`EnqueueDuringReset` errors. Reset requested inside a guest callback follows
the existing deferred Stop/Dispose pattern: the native call waits until the
current callback unwinds, preventing a self-wait when that guest callback runs
on the serialized guest executor. No game-specific hooks were added.

## Verification

Built both frameworks with `LC32_UIKIT_COMPATIBILITY=1` for the host, then ran
ARM32 executables through an isolated command-line runtime in the booted
iOS 27 simulator. No Mac keyboard or mouse input was used. Native macOS
AudioToolbox runs provide reference behavior for the new test cases.

Both framework builds succeeded. Final simulator results: **59/59** queue-control
checks with run-loop callbacks, **59/59** with worker callbacks, **30/30** offline
checks, and **27/27** existing output checks. All four guests exited with code
0. The stream regression also exited 0 with no failures. All three new native
reference runs reported zero failures. `git diff --check` passed.

- `audio_queue_control.c`: normal run-loop and native-worker callback modes;
  repeated reset/reuse, callback-triggered reset, native rejection of enqueue
  during reset, real flush, volume values, property sizes, timestamp translation
  (including in-place output), output canaries and stale queue tokens.
- `audio_queue_offline.c`: trimmed PCM rendering, byte/size copyback, global
  volume, parameterized enqueue, nullable options, aliased timestamp output,
  channel layout, forged-buffer rejection, cleanup and native error parity.
- Existing `audio_queue_output.c`: playback callbacks and re-enqueue are
  required, along with running-property notifications and disposal.
- Existing `audio_file_stream.c`: WAV/AAC parsing and callback regressions
  protect the user-confirmed Asphalt sound-loading fix.
- All nine affected symbols are defined in the built ARM32 framework;
  the complete pre-dispatch/pre-processing-tap AudioQueue C entry-point set
  (29 functions) is exported.

Native reference limitations are intentionally preserved: in the offline test,
the buffer volume event does not override the global volume, and native input
buffers can remain owned by the offline queue until disposal. The bridge does
not fabricate successful buffer release or different PCM output. WAV format
list queries in the stream regression are unsupported by the native parser;
AAC exercises format-list conversion.

Local build/test evidence: `tmp/audio-queue-20260921/` (ignored). The isolated
runtime does not replace other games' selected emulator or alter their data.

## Still outside this patch

The SDK audit still finds these six advanced AudioQueue entry points absent:

- `AudioQueueNewInputWithDispatchQueue`
- `AudioQueueNewOutputWithDispatchQueue`
- `AudioQueueProcessingTapNew`
- `AudioQueueProcessingTapDispose`
- `AudioQueueProcessingTapGetSourceAudio`
- `AudioQueueProcessingTapGetQueueTime`

Those need their own dispatch-block / processing-tap callback and lifetime
bridges. They have not been replaced with fake success stubs. Object-valued or
unknown queue properties also retain the existing unsupported-property result.

The original Asphalt LLDB session was detached and closed; stale LLDB PID
85007 was closed with the user's explicit approval. Xcode and the user's shell
debugger were left alone.
