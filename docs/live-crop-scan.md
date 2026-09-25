# Crop scan: issue #18

The existing section-camera action now reaches `/health/camera`. All other
screens, theme tokens, navigation controls, and manual observation flows are
unchanged. The new screen uses the app's existing buttons, badges, spacing and
light/dark themes.

## Current scope

Live inference is **disabled**, including in demo builds. Issue #16 has not
provided an approved release manifest, Core ML/TFLite artifacts, verified output
tensor contract, or physical-device evidence. The app does not replace that
model with ML Kit's generic object detector. It opens no camera on this route
in normal or demo builds, and keeps manual observations available through the
existing farm screens.

In a `TEST_MODE=true` build, the person can start and stop a clearly labelled
replay. `assets/test_mode/crop_scan.json` contains synthetic crop boxes over
the existing recorded images. These are test annotations, not crop predictions,
condition diagnoses, field accuracy evidence, or a physical benchmark.

The replay exercises:

- Normalized detection validation, canonical crop mapping, class-aware NMS,
  one-to-one tracking, smoothing and time-based track expiry. The original raw
  prompt label is preserved. Low confidence never implies disease.
- Admission of every second frame with one operation in flight, no waiting
  queue, duplicate-timestamp dropping, stale-result rejection and cancellation.
  Backwards, negative and future capture times remain invalid. The core supports every
  third frame. This Dart scheduling contract does not itself move inference to
  a background thread; the future native adapter must do that.
- Neutral crop outlines and orange warning outlines, text/semantic warning
  labels, stable selection and targets of at least 48 logical pixels.
- Measured overlay updates in the trailing second, counted after presentation,
  rather than camera callbacks or inference completions. Replay FPS is not a
  claim about live performance. Camera-to-presentation timing uses one
  monotonic clock.
- Stopping on navigation or backgrounding, no automatic restart on resume,
  and cleanup if an asset finishes loading after the screen closes.

## Model identity gate

`verifyCropRelease` defaults to an empty, code-reviewed release allowlist. A
self-declared `measured` flag is insufficient: the exact release-manifest hash
must be approved, its evidence and preprocessing contract must match, and the
bundled artifact's bytes and SHA-256 must match that manifest. Android uses
the file hash; iOS uses the sorted, length-prefixed package-tree hash from
`vision/export.py`. Tests cross-check an independently generated Python digest.

This gate is preparation for a native loader, not an implemented loader. Adding
an allowlist entry alone does **not** enable live inference. Do not approve the
synthetic test model bytes or use them as shipped detector artifacts.

## Verification

```sh
cd apps/mobile
flutter test --no-pub test/vision test/device
flutter analyze --no-pub
```

The ten-plant slow-pan test checks stable, unique IDs with reordered detections.
Additional tests cover brief misses, expiry, NMS, unknown models, modified
artifacts, overload, late results, cleanup, live/demo gating, large text,
portrait/landscape layouts and both themes.

`e2e/mobile/scan_pan.yaml` uses the standard `TEST_MODE=true` CI build, starting
at Home, opening Cabbage Field and tapping the existing "Scan this section"
action. No `INITIAL_ROUTE` override is needed. It checks a tappable warning box
while panning and absence of a hold-still prompt. `scripts/ci-stack.sh mobile`
runs it after login and a fresh device-readiness check, before stopping the API
for the offline flow. A failed replay fails the job and still cleans up its
owned stack. Widget tests do not substitute for the Maestro run; consult the
`e2e-mobile` result for execution evidence on each commit.

## Remaining issue #18 acceptance

Issue #18 must stay open. After #16's release is reviewed, remaining work is:

1. Bundle the exact approved artifacts and pin the release-manifest digest.
2. Inspect their real tensor outputs and NMS behavior; implement the matching
   Core ML/LiteRT adapters with `load → warmUp → detect → dispose`.
3. Wire the live camera and appropriate device selection, orientation, pixel
   stride/color conversion, RGB letterboxing and inverse box transforms. Keep
   preprocessing, inference and NMS outside the UI thread.
4. Exercise real permission-denied and unsupported-device states. The present
   source-failure tests prove cleanup/error presentation only.
5. Record physical iPhone and Android camera-to-visible-box latency (the
   documented goal is 150 ms), overlay FPS, dropped frames, warm-up, memory,
   artifact identity and offline first launch in airplane mode. Agree the
   required FPS threshold before claiming acceptance; the current issue does
   not provide one.
6. Run the recorded Maestro flow and verify real touch/screen-reader behavior.

No physical measurements or model-accuracy claims have been fabricated.
