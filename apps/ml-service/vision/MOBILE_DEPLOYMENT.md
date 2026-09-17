# Mobile deployment

The release artifact is a fixed prompt export of YOLOE-26n. The export script
bakes the following prompts into the model, so neither platform needs a text
encoder or network access at inference time:

`cabbage plant`, `cabbage head`, `tomato plant`, `tomato fruit`, `spinach plant`.

Use the Core ML artifact in the iOS camera pipeline with CPU and Neural Engine
compute units. Use the LiteRT artifact on Android with the platform delegate
available on the target device. Keep preprocessing, model inference, and NMS
off the UI thread. Bundle the artifact and labels for offline first launch.

Measure the complete camera path on physical devices and record it with:

```bash
python apps/ml-service/vision/benchmark.py --platform ios \
  --device "iPhone 12 Pro" --model v1.coreml --detector-ms 0 \
  --output apps/ml-service/vision/reports/v1-ios.json
```

Replace `0` with the median steady-state detector time measured on the device.
The command fails when the iPhone result exceeds 20 ms. Android results are
recorded by device because Android performance varies by chipset.
