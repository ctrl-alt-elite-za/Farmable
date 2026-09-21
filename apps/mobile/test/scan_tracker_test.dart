import 'package:almanac/features/scan/scan_models.dart';
import 'package:almanac/features/scan/tracker.dart';
import 'package:flutter_test/flutter_test.dart';

Detection detection(double x, {double confidence = 0.9}) => Detection(
  label: 'healthy',
  confidence: confidence,
  box: NormalizedBox(x: x, y: 0.2, width: 0.3, height: 0.5),
);

void main() {
  test('duplicate removal keeps the strongest overlapping detection', () {
    final result = nonMaxSuppression([
      detection(0.1),
      detection(0.11, confidence: 0.6),
      detection(0.7),
    ]);

    expect(result, hasLength(2));
    expect(result.first.confidence, 0.9);
  });

  test('tracker keeps the same id while a crop pans', () {
    final tracker = CropTracker();
    final first = tracker.update([detection(0.1)]).single;
    final second = tracker.update([detection(0.14)]).single;

    expect(second.id, first.id);
  });

  test('tracker retires crops after the missed-frame limit', () {
    final tracker = CropTracker(maxMissedFrames: 1);
    tracker.update([detection(0.1)]);
    expect(tracker.update(const []), isEmpty);
    expect(tracker.update(const []), isEmpty);
    final replacement = tracker.update([detection(0.1)]).single;
    expect(replacement.id, 2);
  });
}
