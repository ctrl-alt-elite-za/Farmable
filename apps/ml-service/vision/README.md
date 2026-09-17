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
matching manifest. The pretrained model is a demo shortcut: it has not been
trained or measured on Farmable field images, does not prove the issue's
per-class accuracy or 300-images-per-crop requirement, and its prompt labels
are not the custom `plant`, `crop_head_or_fruit`, and `check_suggested` label
contract. Treat detections as provisional until a Farmable-labelled model is
trained and evaluated.

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

Record real cabbage and tomato measurements in `weights/cabbage.csv` and
`weights/tomato.csv` with `diameter_cm,weight_g,date`, then run
`python apps/ml-service/vision/eval_weights.py apps/ml-service/vision/weights/cabbage.csv apps/ml-service/vision/weights/tomato.csv`.
Spinach is sold by bunch or kilogram and has no per-plant formula. Do not add
synthetic measurements to satisfy the minimum sample count.

After migration and artifact upload, register the model and verify it from the
backend environment with `python -m app.scripts.detector_model_exists <version>`.
