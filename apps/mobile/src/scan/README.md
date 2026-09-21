# Expo crop scan foundation — not live inference

PR 35 retains the Expo/React Native application on main. Health, Self-test,
native diagnostic probes, and existing CI remain available. A Scan tab adds
the reviewed foundation without reintroducing the reverted Flutter replacement.

## What runs

TEST_MODE replays the existing synthetic crop fixtures locally. It supports
pause/step, reduced motion, same-crop duplicate removal, bounded tracking and
accessible selection controls. Backgrounding stops replay and clears boxes;
returning starts a fresh deterministic session. Mixed test/demo flags fail
before scan initialization. Demo and ordinary builds never replay fixtures.

Live mode explicitly reports that detection is unavailable. On supported native
builds it can show the earlier permission-gated back LiDAR video/depth preview;
unsupported devices explain that limitation. The preview disposes incoming
frames without inference. It does not copy, persist, upload or send scan frames
to an API. Native loading is deferred until Scan and errors are contained there.

The UI matches the existing light Expo shell; it is not a new theme system.
Overlay controls have 48-unit bounds inside the viewport. If a viewport is too
small to contain a control, the overlay is withheld. Text outside the preview
scrolls; fixture selection is informational, not a saved observation or diagnosis.

## Tested boundaries for the later adapter

- `decoder.ts`: application-level normalized-corner decoding, with canonical
  cabbage/tomato/spinach identities and preserved raw prompt labels. The first
  128 candidates are considered to bound malformed-input and overlay work.
  This is not raw Core ML/TFLite tensor decoding or evidence of model approval.
- `tracker.ts`: same-crop NMS/matching, snapshot ownership, stable IDs and bounded
  missed-frame retirement. It cannot diagnose plant health.
- `frameProcessor.ts`: one active operation and one replaceable waiting frame.
  Submission transfers handle ownership exactly once. Replaced/rejected handles
  are released immediately; active handles are released after processing ends.
  Background/disposal invalidates late successes and failures. The current native
  preview does not use this adapter contract to run a model.
- `latency.ts`: one pending presentation acknowledgement, frame/session identity
  checks, chronological finite monotonic timestamps, at most 512 accepted samples,
  and nearest-rank p50/p95. Only matching, nonempty, actually presented overlays
  qualify; replaced/duplicate/stale acknowledgements cannot add samples.

The latency collector is intentionally **not connected to a React commit/RAF
callback**. Such a callback does not prove that pixels reached the display.
The screen reports camera-to-visible-box latency as **unmeasured**. Tests use
injected presentation acknowledgements and cannot substitute for native evidence.
No idle-loop FPS or replay timing is presented as a live camera benchmark.

## Remaining acceptance

Issue 16 must supply the approved, license-reviewed, hashed model artifacts and
their runtime/preprocessing/output handoff, as documented in
`docs/decisions/0016-vision-demo-model.md`. A real native adapter must implement
load/warm-up/detect/dispose, orientation/preview mapping, clock mapping and actual
presentation acknowledgement. Never repeatedly serialize full frames through
React state. Neither a model name nor passing fixture tests proves readiness.

Before live scanning is accepted, verify offline loading/warm-up/inference,
stable boxes during a real crop pan, no frame uploads, physical iPhone p50/p95
camera-to-visible-box latency and the issue 18 engineering goal of under 150 ms.
Native screen-reader, largest-font, reduced-motion, portrait/landscape and
permission/re-entry behavior still require physical-device acceptance. Bundles
and mocked lifecycle tests are not that evidence. Keep issue 18 open and PR 35
unmerged after these corrections. No server endpoint, database migration,
offline observation integration, new model or deployment is part of this slice.
