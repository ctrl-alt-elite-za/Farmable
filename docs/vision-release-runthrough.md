# Vision release run-through

This is the handoff for issue #16. It separates reproducible export checks from
evidence that can only be collected on the target devices. Do not turn desktop
timings or synthetic fixtures into a release report: `benchmark.py` accepts
only `measurement_source=physical_device`, and `release.py` requires matching
artifact/report hashes, an approved license, and two usable detections per
crop.

## 1. Download the pinned checkpoint

The exporter downloads this exact asset when it is not already cached:

```text
https://github.com/ultralytics/assets/releases/download/v8.4.0/yoloe-26n-seg.pt
```

It is YOLOE-26n, exported with the fixed prompts in
`docs/decisions/0016-vision-demo-model.md`. The checkpoint and generated
artifacts are ignored by git; the export manifest records their hashes.

## 2. Export on a supported host

Use the pinned environment from `apps/ml-service/vision/requirements-colab.txt`
with the repository's Python 3.12 toolchain, and enough free disk for PyTorch,
TensorFlow, and the generated artifacts. The
Ultralytics dependency is pinned to the exact revision containing the YOLOE
prompt-fusion export fix; do not substitute `ultralytics==8.4.0`:

```bash
python apps/ml-service/vision/export.py --version demo1 --formats coreml tflite
```

Core ML export must run on macOS. LiteRT/TFLite export requires the pinned
TensorFlow environment. The requirements file includes the pinned macOS-only
Core ML toolchain. The output is `apps/ml-service/vision/models/demo1.*`
plus `demo1.json`; inspect generated tensor shapes, NMS behavior, preprocessing,
and prompt metadata before handing the artifact to mobile.

## 3. Physical reports

Before device runs, build the fixed fixture manifest from supplied real images;
the command records each image hash and never invents detections:

```bash
python apps/ml-service/vision/fixtures.py \
  --root path/to/real-fixtures \
  --output apps/ml-service/vision/reports/demo1-fixture-set.json
```

The fixture directory must contain `cabbage/`, `tomato/`, `spinach/`, and
`negative/`, with at least two images in each directory. These images are
inputs for the later iOS/Android run; this command is not a benchmark and does
not create a passing release report.

After each platform has returned one result object per fixture, assemble the
canonical report consumed by `release.py`:

```bash
python apps/ml-service/vision/fixtures.py \
  --root path/to/real-fixtures \
  --output apps/ml-service/vision/reports/demo1-fixtures.json \
  --ios-results path/to/ios-results.json \
  --android-results path/to/android-results.json \
  --ios-artifact-sha256 '<Core ML SHA-256>' \
  --android-artifact-sha256 '<TFLite SHA-256>'
```

The result files are JSON arrays with `fixture_id`, `detected`, `raw_label`,
and `confidence`; the release validator performs the final schema and
confidence checks.

On the demo iPhone and Android device, collect at least 20 warm inference
samples plus cold load, first inference, and peak memory. Then record them with
`benchmark.py`. The command refuses desktop measurements and computes p50/p95
from the supplied samples.

## 4. Select the release

After the fixed fixture run has produced two ≥0.5-confidence matching results
for cabbage, tomato, and spinach, run `release.py` with the exact approved
license and the report files. It writes an evidence-complete release manifest
without mutating the export manifest.

Until these steps complete, issue #18 can still implement and test against the
documented compact detector contract, but must fail closed rather than loading
an unverified or missing artifact.
