# Live crop scanning

This Flutter port contains the deterministic recorded replay, strict detection
decoder, duplicate removal, lightweight tracker, latest-frame-only processor,
accessible overlay, and camera-to-visible-box latency aggregation.

Issue #18 remains blocked by #16 for the approved `crop-detector-1.tflite`
artifact and its native-buffer inference adapter. Live mode therefore says that
detection is unavailable instead of presenting recorded detections as live.
No scan frame is uploaded or passed to the API.
