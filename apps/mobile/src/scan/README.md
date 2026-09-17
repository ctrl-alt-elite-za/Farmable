# Live-scan implementation status

The tracker, detection decoder, overlay, and recorded test-mode replay are
implemented. Test-mode detections are fixtures, never evidence of live inference.
The camera preview checks permission and selects a back LiDAR video/depth device;
unsupported devices show an explanation instead of silently using another camera.

Issue #18 is not complete and this PR must not close it yet:

- No actual `crop-detector-1.tflite` asset is bundled. The model registry describes
  the intended artifact, not a loaded detector. Issue #16 supplies the real model.
- Live YUV frames are disposed without running inference. Resizing, normalization,
  model execution, orientation/preview-coordinate mapping, and delivery to the
  tracker still need a real model-specific adapter and device verification.
- The self-test cannot benchmark an overlay that is unmounted. It reports FPS as
  unmeasured with an issue note instead of publishing idle animation-loop FPS.
  A mounted-overlay benchmark on the iPhone 12 Pro must demonstrate at least 20 fps.

Recorded replay and mocked camera tests verify control flow only. Do not present
those results as an iPhone crop-pan test or a production detector benchmark.
