import 'dart:async';

import 'package:almanac/features/scan/latest_frame_processor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps only the latest frame while inference is busy', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final processed = <int>[];
    final processor = LatestFrameProcessor<int>((frame) async {
      processed.add(frame);
      if (frame == 7) {
        firstStarted.complete();
        await releaseFirst.future;
      }
    });

    processor.submit(7);
    await firstStarted.future;
    processor
      ..submit(8)
      ..submit(9)
      ..submit(10);
    releaseFirst.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(processed, [7, 10]);
    processor.dispose();
  });

  test('continues with the newest frame after a processing error', () async {
    final processed = <int>[];
    final errors = <Object>[];
    final processor = LatestFrameProcessor<int>((frame) async {
      processed.add(frame);
      if (frame == 1) throw StateError('detector failed');
    }, onError: (error, _) => errors.add(error));

    processor.submit(1);
    await Future<void>.delayed(Duration.zero);
    processor.submit(2);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(processed, [1, 2]);
    expect(errors, hasLength(1));
    processor.dispose();
  });
}
