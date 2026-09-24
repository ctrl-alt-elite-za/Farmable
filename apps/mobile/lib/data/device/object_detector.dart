/// On-device object detection, through Google ML Kit.
///
/// ML Kit bundles its detector model into the app, so detection works with no
/// network and no model download — the same offline promise the rest of the
/// app makes. Later features can hand it a custom TFLite classifier through
/// ML Kit's `LocalModel` without changing this interface.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:path_provider/path_provider.dart';

import 'camera_source.dart';

class DetectionRun {
  final List<Detection> detections;
  final Duration elapsed;

  const DetectionRun(this.detections, this.elapsed);
}

abstract interface class ObjectDetectorService {
  /// Detects objects in the image at [path], timing only the inference.
  Future<DetectionRun> detectFile(String path);

  Future<void> close();
}

class MlKitObjectDetectorService implements ObjectDetectorService {
  ObjectDetector? _detector;

  @override
  Future<DetectionRun> detectFile(String path) async {
    final detector = _detector ??= ObjectDetector(
      options: ObjectDetectorOptions(
        mode: DetectionMode.single,
        classifyObjects: true,
        multipleObjects: true,
      ),
    );
    final input = InputImage.fromFilePath(path);
    final watch = Stopwatch()..start();
    final objects = await detector.processImage(input);
    watch.stop();
    return DetectionRun([
      for (final o in objects)
        Detection(
          label: o.labels.isEmpty ? 'Object' : o.labels.first.text,
          confidence: o.labels.isEmpty ? 0 : o.labels.first.confidence,
          box: o.boundingBox,
        ),
    ], watch.elapsed);
  }

  @override
  Future<void> close() async {
    await _detector?.close();
    _detector = null;
  }
}

/// The self-test's bundled sample image, written to a real file.
///
/// ML Kit reads from a path, and an asset is not a file on the phone until
/// something puts it there.
const sampleImageAsset = 'assets/self_test/sample_field.jpg';

Future<String> materializeSampleImage([AssetBundle? bundle]) async {
  final bytes = await (bundle ?? rootBundle).load(sampleImageAsset);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/self_test_sample_field.jpg');
  await file.writeAsBytes(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    flush: true,
  );
  return file.path;
}
