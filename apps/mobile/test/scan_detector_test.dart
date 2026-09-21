import 'package:almanac/features/scan/detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decoder rejects malformed and low-confidence detections', () {
    final decoded = decodeDetections([
      {
        'label': 'healthy',
        'confidence': 0.9,
        'box': [0.1, 0.2, 0.5, 0.8],
      },
      {
        'label': 'weak',
        'confidence': 0.2,
        'box': [0.1, 0.2, 0.5, 0.8],
      },
      {
        'label': 'outside',
        'confidence': 0.9,
        'box': [-0.1, 0.2, 0.5, 0.8],
      },
      {
        'label': 'backwards',
        'confidence': 0.9,
        'box': [0.8, 0.2, 0.5, 0.8],
      },
      {
        'confidence': 0.9,
        'box': [0.1, 0.2, 0.5, 0.8],
      },
    ]);

    expect(decoded, hasLength(1));
    expect(decoded.single.label, 'healthy');
    expect(decoded.single.box.width, closeTo(0.4, 0.0001));
  });

  test('only allowlisted detector models are accepted', () {
    expect(requireApprovedDetector('crop-detector-1'), 'crop-detector-1');
    expect(
      () => requireApprovedDetector('downloaded-at-runtime'),
      throwsArgumentError,
    );
  });
}
