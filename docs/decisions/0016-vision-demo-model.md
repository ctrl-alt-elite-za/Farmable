# Demo vision model

Status: implementation contract for Issue #16.

Candidate model: the existing YOLOE-26n segmentation checkpoint, with fixed
prompts in this order:

1. `cabbage plant` → `cabbage`
2. `cabbage head` → `cabbage`
3. `tomato plant` → `tomato`
4. `tomato fruit` → `tomato`
5. `spinach plant` → `spinach`

The export environment is pinned to `ultralytics==8.4.0`; the exporter records
the source metadata and checkpoint SHA-256, prompt order, artifact SHA-256 and artifact byte size in
the immutable export manifest. The default precision is FP16 at 640×640. The
manifest remains `measured: false` until physical iOS and Android reports and
a fixed fixture report pass the release gate. The gate writes a separate
`*.release.json` with `evidence_complete: true` and never changes the export
manifest. Evidence completeness is not a performance-readiness claim: raw
inference has no approved ceiling yet, and Issue #18's 150 ms goal covers the
whole camera-to-visible-box path rather than inference alone.

## Runtime contract

The mobile adapter supplies RGB input, resizes with the Ultralytics letterbox
policy, and scales pixels by `1/255`. Detection boxes handed to Flutter use
normalized `x_min, y_min, x_max, y_max` coordinates and preserve the raw prompt
label alongside the canonical crop. This normalized shape is the application
handoff, not a claim about raw model tensors. The export/runtime output tensors and NMS
behavior must be verified from the generated Core ML/TFLite export; the
manifest therefore says `nms: verify_from_export` rather than making an
unverified claim about embedded or external NMS.

Lifecycle for Issue #18 is `load → warmUp → detect → dispose`. The detector is
bundled with the app and must load and infer with the network disabled; a
loading failure should leave manual observation entry available. This issue
does not define camera frame scheduling, tracking, overlay latency, physical
measurement, weight estimation, or disease diagnosis.

## Evidence and limitations

Fixtures are deterministic still images or clips used for qualitative crop-hit
and false-positive checks. They are not a training dataset and do not justify
precision, recall, mAP, field-level accuracy, or agricultural diagnosis claims.
The versioned fixture report hashes every input and records separate runs bound
to the exact Core ML and TFLite artifact hashes. On both platforms, each
required crop needs at least two matching detections at confidence 0.5 or
higher, the set needs at least two negative fixtures, and any detection on a
negative fixture fails selection. These outcomes are derived from raw results,
not accepted as caller-supplied aggregate claims. Selection also fails closed
unless the caller explicitly allowlists the manifest's exact license value. No
license is accepted by default.
Physical reports record cold load, first inference, warm p50/p95, memory,
device/OS/runtime, precision, input size, and artifact identity. Desktop timing
cannot be used as physical-device evidence. The release manifest records the
SHA-256 of each benchmark and fixture report alongside its path.

## Handoff

Issue #18 can load the exact artifact/hash selected in the release manifest and
use its preprocessing, prompt mapping, normalized-box, and lifecycle contract.
Issue #19 may use any segmentation output after a crop is selected, but Issue
#16 does not require continuous full-frame segmentation.
