import 'scan_models.dart';

const approvedDetectorModels = <String, String>{
  'crop-detector-1': 'crop-detector-1.tflite',
};

String requireApprovedDetector(String modelId) {
  if (!approvedDetectorModels.containsKey(modelId)) {
    throw ArgumentError.value(modelId, 'modelId', 'Detector is not approved');
  }
  return modelId;
}

List<Detection> decodeDetections(
  Object? value, {
  double minimumConfidence = 0.35,
}) {
  if (!minimumConfidence.isFinite ||
      minimumConfidence < 0 ||
      minimumConfidence > 1) {
    throw RangeError.range(minimumConfidence, 0, 1, 'minimumConfidence');
  }
  if (value is! List<Object?>) return const [];

  final detections = <Detection>[];
  for (final item in value) {
    if (item is! Map<Object?, Object?>) continue;
    final rawBox = item['box'];
    final label = item['label'];
    final confidence = item['confidence'];
    if (rawBox is! List<Object?> ||
        rawBox.length != 4 ||
        label is! String ||
        confidence is! num) {
      continue;
    }
    final coordinates = rawBox
        .whereType<num>()
        .map((value) => value.toDouble())
        .toList();
    if (coordinates.length != 4 ||
        coordinates.any((coordinate) => !coordinate.isFinite) ||
        !confidence.toDouble().isFinite ||
        confidence < minimumConfidence ||
        confidence > 1) {
      continue;
    }
    final box = NormalizedBox(
      x: coordinates[0],
      y: coordinates[1],
      width: coordinates[2] - coordinates[0],
      height: coordinates[3] - coordinates[1],
    );
    if (box.isValid) {
      detections.add(
        Detection(label: label, confidence: confidence.toDouble(), box: box),
      );
    }
  }
  return detections;
}
