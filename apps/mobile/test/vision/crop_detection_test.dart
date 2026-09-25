import 'dart:ui';

import 'package:almanac/domain/vision/crop_detection.dart';
import 'package:flutter_test/flutter_test.dart';

CropDetection plant(
  double x, {
  double y = 0.1,
  String label = 'cabbage plant',
  double confidence = 0.9,
  bool warning = false,
}) => CropDetection(
  rawLabel: label,
  confidence: confidence,
  box: Rect.fromLTWH(x, y, 0.12, 0.15),
  checkSuggested: warning,
);

void main() {
  test('normalized handoff retains raw label and canonical crop', () {
    final detection = CropDetection.fromJson({
      'raw_label': 'cabbage head',
      'confidence': 0.7,
      'box': {'x_min': 0.1, 'y_min': 0.2, 'x_max': 0.3, 'y_max': 0.4},
    });
    expect(detection.crop, 'cabbage');
    expect(detection.rawLabel, 'cabbage head');
    expect(detection.checkSuggested, isFalse);
  });

  test('rejects unknown crops, nonfinite confidence and invalid boxes', () {
    for (final score in [double.nan, double.infinity, -0.1, 1.1]) {
      expect(() => plant(0.1, confidence: score), throwsFormatException);
    }
    expect(() => plant(0.1, label: 'Object'), throwsFormatException);
    expect(() => plant(-0.1), throwsFormatException);
    expect(() => plant(0.99), throwsFormatException);
    expect(
      () => CropDetection(
        rawLabel: 'tomato plant',
        confidence: 0.8,
        box: Rect.zero,
      ),
      throwsFormatException,
    );
  });

  test('NMS suppresses same-crop prompts, but not another crop', () {
    final kept = suppressCropDuplicates([
      plant(0.1),
      plant(0.1, label: 'cabbage head', confidence: 0.8),
      plant(0.1, label: 'tomato plant'),
      plant(0.4, confidence: 0.49),
    ]);
    expect(kept.map((d) => d.rawLabel), ['cabbage plant', 'tomato plant']);
    expect(kept.every((d) => !d.checkSuggested), isTrue);
  });

  test(
    'ten plants keep distinct IDs across a slow pan and reordered output',
    () {
      final tracker = CropTracker();
      List<int>? originalIds;
      for (var frame = 0; frame < 100; frame++) {
        final detections = [
          for (var i = 0; i < 10; i++)
            plant(
              0.03 + (i % 5) * 0.17 + frame * 0.0004,
              y: 0.1 + (i ~/ 5) * 0.45,
              warning: i == 1,
            ),
        ];
        final tracks = tracker.update(
          frame.isEven ? detections : detections.reversed,
          Duration(milliseconds: frame * 60),
        );
        expect(tracks, hasLength(10));
        originalIds ??= tracks.map((t) => t.id).toList();
        expect(tracks.map((t) => t.id), originalIds);
        for (var i = 0; i < 10; i++) {
          expect(
            tracks[i].detection.box.center.dx,
            closeTo(detections[i].box.center.dx, 0.002),
          );
          expect(tracks[i].detection.checkSuggested, i == 1);
        }
      }
    },
  );

  test(
    'brief misses preserve IDs; expired tracks and reset do not reuse IDs',
    () {
      final tracker = CropTracker();
      final first = tracker.update([plant(0.1)], Duration.zero).single.id;
      expect(
        tracker.update([], const Duration(milliseconds: 100)).single.id,
        first,
      );
      expect(
        tracker
            .update([plant(0.11)], const Duration(milliseconds: 200))
            .single
            .id,
        first,
      );
      expect(tracker.update([], const Duration(milliseconds: 500)), isEmpty);
      final second = tracker
          .update([plant(0.11)], const Duration(milliseconds: 600))
          .single
          .id;
      expect(second, isNot(first));
      tracker.reset();
      expect(
        tracker.update([plant(0.11)], Duration.zero).single.id,
        greaterThan(second),
      );
    },
  );

  test('a track cannot match two detections or another crop', () {
    final tracker = CropTracker();
    tracker.update([plant(0.1)], Duration.zero);
    final next = tracker.update([
      plant(0.12),
      plant(0.2),
      plant(0.1, label: 'tomato plant'),
    ], const Duration(milliseconds: 50));
    expect(next.map((t) => t.id).toSet(), hasLength(3));
  });

  test('rejects backwards time and maps cover-cropped preview coordinates', () {
    final tracker = CropTracker();
    tracker.update([], const Duration(seconds: 1));
    expect(() => tracker.update([], Duration.zero), throwsArgumentError);
    final box = cropPreviewBox(
      const Rect.fromLTRB(0, 0, 1, 1),
      const Size(640, 480),
      const Size(300, 300),
    );
    expect(box, const Rect.fromLTRB(-50, 0, 350, 300));
  });
}
