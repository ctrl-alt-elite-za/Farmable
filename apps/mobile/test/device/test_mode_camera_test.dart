/// Test mode's recorded camera input: the frames and detections a test-mode
/// build plays instead of the live camera.
library;

import 'package:almanac/data/device/camera_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the bundled recording parses, and every frame it names is bundled',
    () async {
      final session = await RecordedSession.load(rootBundle);
      expect(session.frames, isNotEmpty);
      for (final frame in session.frames) {
        final bytes = await rootBundle.load(frame.asset);
        expect(bytes.lengthInBytes, greaterThan(0), reason: frame.asset);
      }
    },
  );

  test('recorded detections come back in frame pixels, like a live '
      "detector's", () async {
    final session = await RecordedSession.load(rootBundle);
    final box = session.frames.first.detections.first.box;
    expect(box.left, greaterThanOrEqualTo(0));
    expect(box.right, lessThanOrEqualTo(session.width.toDouble()));
    expect(box.bottom, lessThanOrEqualTo(session.height.toDouble()));
    // Fractions would all be below 1. Pixels are not.
    expect(box.width, greaterThan(1));
  });

  test(
    'the recorded source says it is recorded, plays frames and loops',
    () async {
      final source = RecordedCameraSource();
      expect(source.isRecorded, isTrue);
      final frames = <CameraFrame>[];
      final sub = source.frames.listen(frames.add);
      await source.open();
      final session = await RecordedSession.load(rootBundle);
      await Future<void>.delayed(
        session.interval * (session.frames.length + 1) +
            const Duration(milliseconds: 50),
      );
      await sub.cancel();
      await source.close();

      expect(frames.length, greaterThan(session.frames.length));
      expect(frames.first.width, session.width);
      // Looped back to the start rather than stopping on the last frame.
      expect(source.current.value, lessThan(session.frames.length));
      expect(source.currentDetections, isNotEmpty);
    },
  );

  test('the self-test sample picture is bundled', () async {
    final bytes = await rootBundle.load('assets/self_test/sample_field.jpg');
    expect(bytes.lengthInBytes, greaterThan(1000));
  });
}
