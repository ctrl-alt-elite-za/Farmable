# Mobile deployment

The demo release artifact is a fixed-prompt export of the pretrained YOLOE-26n
model. The export script
bakes the following prompts into the model, so neither platform needs a text
encoder or network access at inference time:

`cabbage plant`, `cabbage head`, `tomato plant`, `tomato fruit`, `spinach plant`.

Use the `.mlpackage` Core ML artifact in the iOS camera pipeline with CPU and Neural Engine
compute units. Use the LiteRT artifact on Android with the platform delegate
available on the target device. Keep preprocessing, model inference, and NMS
off the UI thread. Bundle the artifact and labels for offline first launch.

This is intentionally a provisional demo model. It has no Farmable field-data
accuracy report, may miss local varieties and conditions, and does not provide
the issue's custom condition label or measured weight functionality. Do not
describe it as satisfying the training and evaluation acceptance criteria.

Issue #16 records detector measurements (not the complete camera path; that is
Issue #18) on physical devices. First collect a JSON array of at least 20 warm inference
milliseconds, for example `ios-warm.json`, then record the report with:

```bash
python apps/ml-service/vision/benchmark.py --platform ios \
  --device "iPhone 12 Pro" --os-version "<exact iOS version>" \
  --runtime "Core ML" --precision fp16 --model-version demo1 \
  --artifact-sha256 "<manifest SHA-256>" --artifact-bytes "<manifest bytes>" \
  --cold-load-ms "<measured>" --first-inference-ms "<measured>" \
  --warm-samples-file ios-warm.json --warmup-iterations 10 \
  --peak-memory-mb "<measured>" --measurement-source physical_device \
  --output apps/ml-service/vision/reports/demo1-ios.json
```

The tool computes warm p50 and p95 and rejects missing, non-positive, non-finite
or non-physical measurements. Android uses the same fields with the exact
target device/runtime. The old 20 ms iPhone value is a useful stretch target,
not a release gate by itself.

After both reports exist, produce a separate selected release manifest only
after the fixed fixture report is complete:

```bash
python apps/ml-service/vision/release.py \
  --manifest apps/ml-service/vision/models/demo1.json \
  --ios-report apps/ml-service/vision/reports/demo1-ios.json \
  --android-report apps/ml-service/vision/reports/demo1-android.json \
  --fixtures apps/ml-service/vision/reports/demo1-fixtures.json \
  --output apps/ml-service/vision/models/demo1.release.json
```

Each fixture result records `fixture_id`, `expected_crop` (`cabbage`, `tomato`,
`spinach`, or `null` for a negative), `detected`, the configured `raw_label`,
`confidence`, and `false_positive`. A crop marked `usable` must have at least
one matching detected fixture; this remains qualitative demo evidence, not an
accuracy percentage.
