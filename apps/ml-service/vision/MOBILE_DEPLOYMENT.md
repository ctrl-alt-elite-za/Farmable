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

Measure the complete camera path on physical devices and record it with:

```bash
python apps/ml-service/vision/benchmark.py --platform ios \
  --device "iPhone 12 Pro" --model v1.mlpackage --detector-ms 12.4 \
  --measurement-source physical_device \
  --output apps/ml-service/vision/reports/v1-ios.json
```

Replace `12.4` with the median steady-state detector time measured on the device.
The command fails when the iPhone result exceeds 20 ms. Android results are
recorded by device because Android performance varies by chipset.
