# Vision pipeline

## Pretrained mobile demo

The quickest working path uses the pretrained YOLOE-26n segmentation model;
no private training dataset is required. Ultralytics downloads
`yoloe-26n-seg.pt` on first use, and the exporter bakes the crop prompts into
offline mobile artifacts:

```bash
python apps/ml-service/vision/export.py --version demo1 \
  --formats coreml tflite
```

This produces `demo1.mlpackage` for iOS and `demo1.tflite` for Android. The
phone app still needs its Core ML or LiteRT camera adapter and must bundle the
matching manifest. The export manifest records the pinned Ultralytics source
metadata, source checkpoint hash, exact prompt order, runtime input/output contract, artifact hashes
and byte sizes; it remains `measured: false` until physical-device reports and
a fixed fixture report are available. The separate evidence gate writes
`demo1.release.json` without mutating the export manifest.

This is a pretrained demo shortcut, not a Farmable field-data accuracy claim:
it may miss local varieties, lighting and occlusion, and it does not diagnose
disease or estimate weight. Fixtures are qualitative regression evidence, not
a substitute for a labelled training/evaluation dataset.

Organise the private dataset as `data/<version>/{train,test}/images` with an
`image_sessions.csv` manifest containing `image,session_id,crop` columns. Validate
the session split before training:

```bash
python apps/ml-service/vision/check_split.py --train data/v1/train/images --test data/v1/test/images --manifest data/v1/image_sessions.csv
```

`train.py` uses a fixed seed and requires a separately managed, pinned
Ultralytics/TFLite training environment (for example Colab). It writes a
versioned report and can export TFLite; provide the actual train/test image
directories and the CSV manifest. It validates the real session split, labels,
and image counts rather than trusting a separate claims file. It does not
download data in CI. Install the exact versions in
`requirements-colab.txt`.

The `--data` YAML must name the same single local image directories as
`--train-images` and `--test-images`, and list the ordered class names
`plant`, `crop_head_or_fruit`, `check_suggested`. A relative `path` is resolved
beside the YAML file; split paths are relative to that dataset root. Include
`val` (or `validation`) as a local image directory; image-list files, archives
and downloads are not supported by this audited training entry point.
Training and evaluation use the same absolute-path snapshot saved as
`runs/<version>.data.yaml` (gitignored); the source YAML is not modified.
Reports map metrics through actual class IDs and retain null metrics for
classes absent from the test split.

Record real cabbage and tomato measurements in `weights/cabbage.csv` and
`weights/tomato.csv` with `diameter_cm,weight_g,date`, then run
`python apps/ml-service/vision/eval_weights.py apps/ml-service/vision/weights/cabbage.csv apps/ml-service/vision/weights/tomato.csv`.
Spinach is sold by bunch or kilogram and has no per-plant formula. Do not add
synthetic measurements to satisfy the minimum sample count.

After migration and artifact upload, register the model and verify it from the
backend environment with `python -m app.scripts.detector_model_exists <version>`.
