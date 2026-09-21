class NormalizedBox {
  final double x;
  final double y;
  final double width;
  final double height;

  const NormalizedBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  bool get isValid =>
      x >= 0 &&
      y >= 0 &&
      width > 0 &&
      height > 0 &&
      x + width <= 1 &&
      y + height <= 1;
}

class Detection {
  final String label;
  final double confidence;
  final NormalizedBox box;

  const Detection({
    required this.label,
    required this.confidence,
    required this.box,
  });
}

class CropTrack extends Detection {
  final int id;
  final int missedFrames;

  const CropTrack({
    required this.id,
    required super.label,
    required super.confidence,
    required super.box,
    this.missedFrames = 0,
  });

  CropTrack missed() => CropTrack(
    id: id,
    label: label,
    confidence: confidence,
    box: box,
    missedFrames: missedFrames + 1,
  );
}

class ScanFrame {
  final int sequence;
  final DateTime capturedAt;
  final Object detectorOutput;

  const ScanFrame({
    required this.sequence,
    required this.capturedAt,
    required this.detectorOutput,
  });
}
