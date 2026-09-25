import 'dart:async';

import 'package:almanac/domain/vision/crop_detection.dart';
import 'package:almanac/domain/vision/crop_frame_processor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final stride in [2, 3]) {
    test(
      'duplicate timestamps are dropped without changing stride $stride',
      () async {
        var now = Duration.zero;
        var calls = 0;
        final pending = Completer<List<CropDetection>>();
        final processor = CropFrameProcessor(
          clock: () => now,
          frameStride: stride,
        );
        Future<List<CropDetection>> infer() async {
          calls++;
          return [];
        }

        final first = processor.process(
          capturedAt: now,
          infer: () {
            calls++;
            return pending.future;
          },
        );
        expect(await processor.process(capturedAt: now, infer: infer), isNull);
        pending.complete([]);
        expect(await first, isNotNull);
        expect(await processor.process(capturedAt: now, infer: infer), isNull);
        expect(calls, 1);
        expect(processor.droppedFrames, 2);

        for (var i = 1; i < stride; i++) {
          now = Duration(milliseconds: i);
          expect(
            await processor.process(capturedAt: now, infer: infer),
            isNull,
          );
        }
        now = Duration(milliseconds: stride);
        final result = await processor.process(capturedAt: now, infer: infer);
        expect(result?.frameId, stride);
        expect(calls, 2);
      },
    );
  }

  for (final invalid in [-1, 9, 21]) {
    test('invalid capture time ${invalid}ms is still rejected', () async {
      final processor = CropFrameProcessor(
        clock: () => const Duration(milliseconds: 20),
      );
      await processor.process(
        capturedAt: const Duration(milliseconds: 10),
        infer: () async => [],
      );
      await expectLater(
        processor.process(
          capturedAt: Duration(milliseconds: invalid),
          infer: () async =>
              throw StateError('must not infer an invalid frame'),
        ),
        throwsArgumentError,
      );
      expect(processor.droppedFrames, 0);
    });
  }

  test(
    'slow inference drops arrivals without converting or building a queue',
    () async {
      var now = Duration.zero;
      var calls = 0;
      final pending = Completer<List<CropDetection>>();
      final processor = CropFrameProcessor(clock: () => now);
      final first = processor.process(
        capturedAt: now,
        infer: () {
          calls++;
          return pending.future;
        },
      );
      for (var i = 1; i <= 6; i++) {
        now = Duration(milliseconds: i * 10);
        expect(
          await processor.process(
            capturedAt: now,
            infer: () async {
              calls++;
              return [];
            },
          ),
          isNull,
        );
      }
      expect(calls, 1);
      pending.complete([]);
      expect(await first, isNotNull);
      await pumpEventQueue();
      expect(calls, 1);
      expect(processor.droppedFrames, 6);
      now = const Duration(milliseconds: 70);
      expect(
        await processor.process(
          capturedAt: now,
          infer: () async {
            calls++;
            return [];
          },
        ),
        isNull,
      );
      now = const Duration(milliseconds: 80);
      expect(
        await processor.process(
          capturedAt: now,
          infer: () async {
            calls++;
            return [];
          },
        ),
        isNotNull,
      );
      expect(calls, 2);
    },
  );

  test(
    'stale result is discarded and exceptions release the busy slot',
    () async {
      var now = Duration.zero;
      final processor = CropFrameProcessor(clock: () => now, frameStride: 3);
      expect(
        await processor.process(
          capturedAt: now,
          infer: () async {
            now = const Duration(milliseconds: 151);
            return [];
          },
        ),
        isNull,
      );
      for (var i = 1; i <= 2; i++) {
        now += const Duration(milliseconds: 1);
        await processor.process(capturedAt: now, infer: () async => []);
      }
      now += const Duration(milliseconds: 1);
      await expectLater(
        processor.process(
          capturedAt: now,
          infer: () async => throw StateError('failed'),
        ),
        throwsStateError,
      );
      for (var i = 4; i <= 6; i++) {
        now += const Duration(milliseconds: 1);
        final result = await processor.process(
          capturedAt: now,
          infer: () async => [],
        );
        if (i == 6) expect(result, isNotNull);
      }
    },
  );

  test('close discards an in-flight result and accepts no more work', () async {
    final pending = Completer<List<CropDetection>>();
    final processor = CropFrameProcessor(clock: () => Duration.zero);
    final first = processor.process(
      capturedAt: Duration.zero,
      infer: () => pending.future,
    );
    processor.close();
    pending.complete([]);
    expect(await first, isNull);
    expect(
      await processor.process(
        capturedAt: Duration.zero,
        infer: () async => throw StateError('must not run'),
      ),
      isNull,
    );
  });

  test(
    'FPS counts actual unique presentations, expires and rejects late paints',
    () async {
      var now = Duration.zero;
      final processor = CropFrameProcessor(clock: () => now);
      final result = (await processor.process(
        capturedAt: now,
        infer: () async => [],
      ))!;
      expect(processor.overlayFps, 0);
      now = const Duration(milliseconds: 20);
      expect(processor.markPresented(result), now);
      expect(processor.markPresented(result), isNull);
      expect(processor.overlayFps, 1);
      now = const Duration(milliseconds: 1020);
      expect(processor.overlayFps, 0);
      expect(processor.markPresented(result), isNull);
    },
  );
}
