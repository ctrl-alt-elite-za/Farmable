Reports are generated locally and committed only after review. Issue #16
physical-device benchmark reports contain artifact identity, device/runtime,
cold load, first inference, warm samples and p50/p95, and peak memory. Its
fixed-fixture report hashes every fixture, binds separate iOS and Android runs
to their exact artifact hashes, and records raw qualitative detections. Crop
hits and negative false positives are derived by the release gate rather than
accepted as aggregate claims. This evidence does not claim precision, recall,
or mAP.

Future training reports are separate evidence and include per-class
`precision`, `recall`, and `map50`, plus disjoint train/test session lists. No
model weights, raw farmer images, or private dataset images belong here.
