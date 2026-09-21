# PR 35: preserve Expo and correct the scan foundation

## Decision and scope

The requester approved retaining Expo/React Native, adapting PR 35's scan
foundation to it, and correcting latency reporting with regression tests.
This document specifies that correction; implementation waits for written-spec
approval. PR 35 must remain unmerged after the changes. Do not enable auto-merge.

Review baseline: PR head `1ab32f4f6985eb34bde5136aaafdb28fb6b45c20`;
current inspected main `e32a53e`. Main still contains the Expo app after PR 44's
backend authentication merge. PR 35's description incorrectly treats PR 44 as
having established a Flutter frontend. Issue 18 mentions Flutter, but that is
not authorization to replace the actual main-branch app in this correction.
Document the chosen Expo integration and this discrepancy in the PR handoff.

Alternatives considered: keep the Flutter rewrite, which needs a separate
migration decision and equivalent native verification; or defer all scan work
until the detector is ready. The selected approach preserves existing app
capabilities while making the reusable scan foundation independently testable.
It does not claim to complete live crop scanning or issue 18.

## Integration boundary

- Incorporate current main into the PR branch without rewriting shared history.
  Recheck the remote head first and preserve any intervening contributor changes.
- Restore the Expo application, dependencies/lockfile, entry point, build-mode
  policy, Health and Self-test screens, native diagnostic implementations, and
  their tests from the updated main baseline. Remove the Flutter replacement
  introduced by this PR from the resulting tracked tree, not from git history.
- Keep the main-branch Expo CI, native builds, Maestro flows, required-check
  policy, and dependency/configuration guards. Do not weaken checks to obtain a
  green result. Read `docs/ci.md` before any necessary CI adjustment.
- Add the scan entry alongside existing navigation. Reuse the earlier Expo scan
  foundation in this PR's history where suitable, but re-review its behavior;
  restoring old code is not evidence that it meets the current requirements.
- Keep backend/authentication, migrations, deployment, and vision-release
  tooling at the integrated main baseline. Do not restore old versions merely
  because this branch predates their merge. Do not pull unrelated test changes
  into the final diff. Do not modify or merge PR 47's offline queue.

## Scan components and data flow

Use separate TypeScript units for detection validation, duplicate suppression,
tracking, latest-frame scheduling, timing aggregation, and the React Native
screen/overlay. Their tests must not require camera hardware or a real model.

The processing boundary accepts a frame identity, session identity, monotonic
capture timestamp, and an owned frame handle. Processing returns compact
detections and timing metadata, not full images serialized through React state.
Retain one in-flight operation and only the newest waiting frame. Replacing a
waiting frame releases it exactly once. Disposal rejects new work, releases
waiting resources, and prevents late results from changing the UI or metrics;
the in-flight resource is released when processing actually finishes, not while
the detector might still be using it. An error must not leave the runner stuck.
This scheduler is a tested boundary, not a claim that native inference exists.

Validate finite confidence and normalized positive-area boxes before tracking.
Suppress duplicates only within the same canonical crop class. Match tracks
within that class, preserve IDs while panning, and retire stale tracks after a
bounded missed-frame count. Do not turn crop identity into a disease or health
diagnosis. Fixture labels and notices must not imply that the selected crop
detector diagnoses a plant as healthy or unhealthy.

Recorded replay remains deterministic and restricted to TEST_MODE. Reject
mixed test/demo flags before starting a camera or replay timer. Live mode must
never fall back to recorded detections. Retain the existing permission/device
handling for any preview; preview availability is not detector readiness.
Pause replay/processing when the screen is inactive or the app backgrounds;
dispose resources and invalidate the session on navigation away.

## Model and privacy constraints

Issue 16 still owns the real artifact, license approval, hashes, preprocessing,
runtime output contract, and physical-device evidence. Follow the integrated
`docs/decisions/0016-vision-demo-model.md` handoff; a hard-coded model name is
not proof that an approved artifact exists or has been loaded/warmed.

This change does not download or choose a replacement model, fabricate a model
manifest, or introduce a pretend native inference adapter. Production reports
live detection as unavailable until a reviewed load/warm-up/detect/dispose
implementation and its artifact are supplied. No scan image is uploaded or
sent to an API. Keep this privacy boundary explicit in code, tests, and UI.

## Correct timing semantics

Attach timing to session/frame identity through capture, inference start/end,
and overlay acknowledgement. Use a single monotonic time basis; reject
non-finite, negative, or out-of-order timing data. Native capture times from a
different clock need an explicit mapping before they can be compared.

A sample is accepted once, only for the matching frame/session acknowledged
by the overlay, with at least one displayed detection. A frame replaced before
acknowledgement, a stale callback, a duplicate callback, a zero-detection frame,
or an unmounted overlay must not contribute a visible-box latency sample.
Keep at most 512 accepted samples and one pending overlay acknowledgement,
and reset both on a new session. Compute p50/p95 by nearest rank: sort the
samples and select zero-based index `ceil(p * sampleCount) - 1` for `p = 0.50`
or `0.95`. An empty sample window produces no measured summary.

React render/commit or requestAnimationFrame callbacks alone do not prove that
a frame reached the display. The reusable collector may accept an injected
presentation acknowledgement in tests, but production camera-to-visible-box
latency stays **unmeasured** until a native presentation measurement exists.
If replay/JS timing is exposed, label it as a replay/JS diagnostic, not
`camera_to_visible_box_ms`, an inference benchmark, or real-device acceptance.
Preserve the existing refusal to publish idle-loop FPS as mounted-overlay FPS.

## Interface constraints

Preserve the current app's navigation and styling rather than adding a separate
design system. The scan entry, unavailable state, and test-mode indicator must
be understandable without color alone. Overlay actions use descriptive labels,
button semantics, and at least 48-by-48 logical-unit touch targets, positioned
inside the viewport even when boxes touch its edges. Do not rely on hitSlop
outside a clipped parent to satisfy the target size. Preserve safe areas and
support a small viewport and enlarged text without hiding navigation.

## Verification and handoff

Add regression coverage for:

- Health/Self-test navigation and existing native diagnostic behavior surviving
  the scan addition; production/test replay separation and invalid build flags.
- Malformed detections, same-class duplicate suppression, class-safe matching,
  stable tracking IDs, and bounded stale-track retirement.
- Latest-frame replacement during slow processing, exactly-once resource release,
  processing errors, background/disposal, and late result suppression.
- Matching presentation identities, coalesced frames, duplicate/stale callbacks,
  empty detections, invalid clocks, bounded storage, and percentile calculations.
- Accessible overlay controls and viewport-edge placement; no scan-frame network
  calls and no production live-performance claim derived from fixture timing.

Run the complete Expo mobile tests, targeted script/CI-policy tests, repository
lint/type checks, formatting, and relevant native bundle/config checks. Verify
the final diff preserves unrelated main-branch changes. Report checks against
the actual pushed commit, distinguishing local tests, bundles, CI builds, and
physical-device evidence. No test quarantine or relaxed assertions to hide a
failure. No deployment or live database changes.

Update PR 35's title/description to reflect Expo-preserving foundation work,
state why the Flutter replacement was removed, list verification and remaining
model/device blockers, and keep issue 18 open. Existing changes-requested review
must not be dismissed just because unit tests pass. Neither actual offline
inference nor the iPhone camera-to-visible-box target is complete in this scope.
