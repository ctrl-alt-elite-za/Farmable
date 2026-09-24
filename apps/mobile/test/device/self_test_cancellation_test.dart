/// Stopping the self-test, and what a stopped or timed-out check may still do.
///
/// The answer is: nothing. After the screen is left, the app goes to the
/// background or a check times out, no later check may start, no permission
/// may be asked, no audio may play and no report may be written — and the
/// hardware the stuck check had open is released anyway.
library;

import 'dart:async';

import 'package:almanac/app/theme/app_theme.dart';
import 'package:almanac/features/self_test/self_test_controller.dart';
import 'package:almanac/features/self_test/self_test_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/device_fakes.dart';

/// Calls that would mean the run carried on after it should have stopped.
const _laterHardware = [
  'ar.run',
  'mic.permission',
  'mic.record',
  'mic.play',
  'detector.run',
  'location.fix',
];

Future<void> _advance(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

void main() {
  group('leaving the screen stops the run', () {
    testWidgets('during camera start-up: camera released, nothing after', (
      tester,
    ) async {
      final log = HardwareCalls();
      final store = MemoryStore();
      final controller = SelfTestController(
        healthyPhone(
          log,
          store: store,
          camera: () => FakeCamera(log, hangOnOpen: true),
        ),
      );
      unawaited(controller.run());
      await tester.pump(const Duration(seconds: 1));
      expect(log.calls, ['camera.open']);

      controller.dispose();
      await _advance(tester, const Duration(minutes: 3));

      expect(log.calls, contains('camera.close'));
      for (final call in _laterHardware) {
        expect(log.calls, isNot(contains(call)), reason: call);
      }
      expect(store.saved, isEmpty);
    });

    testWidgets('during AR: the native session is cancelled, nothing after', (
      tester,
    ) async {
      final log = HardwareCalls();
      final store = MemoryStore();
      final controller = SelfTestController(
        healthyPhone(log, store: store, ar: FakeAr(log, hang: true)),
      );
      unawaited(controller.run());
      await _advance(tester, const Duration(seconds: 2));
      expect(log.calls.last, 'ar.run');

      controller.dispose();
      await _advance(tester, const Duration(minutes: 3));

      expect(log.calls, contains('ar.cancel'));
      for (final call in _laterHardware.skip(1)) {
        expect(log.calls, isNot(contains(call)), reason: call);
      }
      expect(store.saved, isEmpty);
    });

    testWidgets('during recording: microphone released, no playback, '
        'nothing after', (tester) async {
      final log = HardwareCalls();
      final store = MemoryStore();
      final release = Completer<void>();
      final controller = SelfTestController(
        healthyPhone(
          log,
          store: store,
          audio: () => FakeAudio(log, releaseRecording: release),
        ),
      );
      unawaited(controller.run());
      await _advance(tester, const Duration(seconds: 2));
      expect(log.calls.last, 'mic.record');

      controller.dispose();
      await tester.pump();
      expect(log.calls, contains('mic.dispose'));

      // The recording finishing late must not start playback.
      release.complete();
      await _advance(tester, const Duration(minutes: 3));

      expect(log.calls, isNot(contains('mic.play')));
      expect(log.calls, isNot(contains('detector.run')));
      expect(log.calls, isNot(contains('location.fix')));
      expect(store.saved, isEmpty);
    });
  });

  testWidgets('the app going to the background stops the run and says so', (
    tester,
  ) async {
    final log = HardwareCalls();
    final store = MemoryStore();
    final release = Completer<void>();
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: almanacLightTheme(),
        home: SelfTestScreen(
          devices: healthyPhone(
            log,
            store: store,
            audio: () => FakeAudio(log, releaseRecording: release),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Run self-test'));
    await _advance(tester, const Duration(seconds: 2));
    expect(log.calls.last, 'mic.record');

    // A permission prompt only makes the app inactive; that must not stop it.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byKey(const Key('self-test-stopped')), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(log.calls, contains('mic.dispose'));
    release.complete();
    await _advance(tester, const Duration(minutes: 3));

    // Back in the app — nothing draws while it is paused — the person is
    // told why the test stopped.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(const Key('self-test-stopped')), findsOneWidget);
    expect(log.calls, isNot(contains('mic.play')));
    expect(store.saved, isEmpty);
    // Stopped, not stuck: it can be run again.
    expect(find.text('Run self-test'), findsOneWidget);
  });

  group('a check that times out', () {
    testWidgets('and never completes: its hardware is released and the run '
        'finishes', (tester) async {
      final log = HardwareCalls();
      final store = MemoryStore();
      final controller = SelfTestController(
        healthyPhone(
          log,
          store: store,
          audio: () => FakeAudio(log, hangOnRecord: true),
          permissionTimeout: const Duration(seconds: 10),
        ),
      );
      unawaited(controller.run());
      await _advance(tester, const Duration(seconds: 30));

      expect(log.calls, contains('mic.dispose'));
      expect(controller.phase, SelfTestPhase.done);
      expect(controller.isRunning, isFalse);
      expect(store.saved, hasLength(1));
      controller.dispose();
    });

    testWidgets('and completes afterwards: no playback, and a finished run '
        'stays finished', (tester) async {
      final log = HardwareCalls();
      final release = Completer<void>();
      final controller = SelfTestController(
        healthyPhone(
          log,
          audio: () => FakeAudio(log, releaseRecording: release),
          permissionTimeout: const Duration(seconds: 10),
        ),
      );
      unawaited(controller.run());
      await _advance(tester, const Duration(seconds: 30));
      expect(controller.phase, SelfTestPhase.done);

      release.complete();
      await _advance(tester, const Duration(seconds: 10));

      expect(log.calls, isNot(contains('mic.play')));
      expect(controller.phase, SelfTestPhase.done);
      expect(controller.isRunning, isFalse);
      controller.dispose();
    });
  });
}
