/// The self-test screen, driven end to end against fake hardware.
///
/// The promises under test are the ones issue #4 makes: every check ends in
/// pass, fail or "not supported"; a phone without a capability — or an
/// emulator without any — never crashes the screen; and nothing is asked of
/// the hardware until the person taps Run.
library;

import 'package:almanac/app/router.dart';
import 'package:almanac/app/theme/app_theme.dart';
import 'package:almanac/data/device/ar_probe.dart';
import 'package:almanac/domain/device/permission_copy.dart';
import 'package:almanac/domain/device/self_test.dart';
import 'package:almanac/features/self_test/self_test_controller.dart';
import 'package:almanac/features/self_test/self_test_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/device_fakes.dart';

/// Tall enough that every row is built: the screen is a lazy ListView, and a
/// row scrolled off a phone-sized surface would not exist to be found.
Future<void> _pump(WidgetTester tester, SelfTestDevices devices) async {
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: almanacLightTheme(),
      home: SelfTestScreen(devices: devices),
    ),
  );
}

/// Pumps fake time forward until the run finishes. The checks wait on real
/// durations (a 3-second recording, a preview hold), all under the test's fake
/// clock, so this is fast.
Future<void> _runToEnd(WidgetTester tester) async {
  await tester.tap(find.text('Run self-test'));
  for (var i = 0; i < 400; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text('Run again').evaluate().isNotEmpty) return;
  }
  fail('The self-test never finished.');
}

String _outcome(WidgetTester tester, SelfTestItem item) => tester
    .widget<OutcomePill>(find.byKey(Key('self-test-${item.name}-outcome')))
    .label;

void main() {
  testWidgets('asks nothing of the hardware until Run is tapped', (
    tester,
  ) async {
    final log = HardwareCalls();
    await _pump(tester, healthyPhone(log));
    await tester.pump(const Duration(seconds: 5));

    expect(log.calls, isEmpty);
    for (final item in SelfTestItem.values) {
      expect(_outcome(tester, item), 'Not run yet');
    }
    // What each permission is for is on screen before any prompt can be.
    expect(
      find.textContaining(PermissionCopy.camera, findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(PermissionCopy.microphone, findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(PermissionCopy.location, findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a working phone passes every check, in order', (tester) async {
    final log = HardwareCalls();
    final store = MemoryStore();
    await _pump(tester, healthyPhone(log, store: store));
    await _runToEnd(tester);

    for (final item in SelfTestItem.values) {
      expect(_outcome(tester, item), 'Pass', reason: item.label);
    }
    expect(find.textContaining('Found 2 surfaces'), findsOneWidget);
    expect(find.textContaining('then 42 ms'), findsOneWidget);
    expect(find.text('This phone passed'), findsOneWidget);

    // Camera is released before AR opens it: only one client may hold it.
    expect(
      log.calls.indexOf('camera.close'),
      lessThan(log.calls.indexOf('ar.run')),
    );
    expect(log.calls, containsAllInOrder(['mic.record', 'mic.play']));

    final report = store.saved.single.toJson();
    expect(report['overall'], 'pass');
    expect(report['detector_ms'], 42);
    expect(report['notes'], isEmpty);
  });

  testWidgets('an emulator with nothing gets "not supported", never a crash', (
    tester,
  ) async {
    final log = HardwareCalls();
    final store = MemoryStore();
    await _pump(tester, bareEmulator(log, store: store));
    await _runToEnd(tester);

    for (final item in SelfTestItem.values) {
      expect(
        _outcome(tester, item),
        'Not supported on this phone',
        reason: item.label,
      );
    }
    expect(tester.takeException(), isNull);
    // Not supported is an answer, not a failure: the phone still passes.
    final report = store.saved.single.toJson();
    expect(report['overall'], 'pass');
    expect(report['camera_preview'], 'unsupported');
    expect(report['lidar_depth'], 'unsupported');
    expect(report['ar_plane'], 'unsupported');
    expect(report['mic_record'], 'unsupported');
    expect(report['detector_ms'], isNull);
    expect(report['notes'], hasLength(SelfTestItem.values.length));
  });

  testWidgets('a phone with ARCore but no depth: AR passes, depth is '
      'not supported', (tester) async {
    final log = HardwareCalls();
    await _pump(
      tester,
      healthyPhone(
        log,
        ar: FakeAr(
          log,
          facts: const ArProbeFacts(
            arAvailable: true,
            planesDetected: 1,
            trackingFrames: 12,
          ),
        ),
      ),
    );
    await _runToEnd(tester);

    expect(_outcome(tester, SelfTestItem.arPlane), 'Pass');
    expect(_outcome(tester, SelfTestItem.depth), 'Not supported on this phone');
  });

  testWidgets('refused permissions fail with a reason, and the run goes on', (
    tester,
  ) async {
    final log = HardwareCalls();
    await _pump(
      tester,
      healthyPhone(
        log,
        audio: () => FakeAudio(log, permission: false),
        ar: FakeAr(
          log,
          facts: const ArProbeFacts(arAvailable: true, cameraPermission: false),
        ),
      ),
    );
    await _runToEnd(tester);

    expect(_outcome(tester, SelfTestItem.microphone), 'Fail');
    expect(
      find.textContaining('Microphone permission was refused'),
      findsOneWidget,
    );
    expect(_outcome(tester, SelfTestItem.arPlane), 'Fail');
    expect(find.text('Something on this phone did not work'), findsOneWidget);
    // A refused microphone is not recorded from.
    expect(log.calls, isNot(contains('mic.record')));
    // Later checks still ran.
    expect(_outcome(tester, SelfTestItem.detector), 'Pass');
    expect(_outcome(tester, SelfTestItem.location), 'Pass');
  });

  testWidgets('a hung check fails on its timeout instead of hanging the '
      'screen', (tester) async {
    final log = HardwareCalls();
    await _pump(
      tester,
      healthyPhone(
        log,
        audio: () => FakeAudio(log, hangOnRecord: true),
        permissionTimeout: const Duration(seconds: 10),
      ),
    );
    await _runToEnd(tester);

    expect(_outcome(tester, SelfTestItem.microphone), 'Fail');
    expect(
      find.textContaining('Did not finish within 10 seconds'),
      findsOneWidget,
    );
  });

  testWidgets('a silent recording is played back but does not pass', (
    tester,
  ) async {
    final log = HardwareCalls();
    await _pump(
      tester,
      healthyPhone(log, audio: () => FakeAudio(log, peak: -160)),
    );
    await _runToEnd(tester);

    expect(log.calls, contains('mic.play'));
    expect(_outcome(tester, SelfTestItem.microphone), 'Fail');
    expect(find.textContaining('it was silent'), findsOneWidget);
  });

  testWidgets('an AR plugin that throws is a failure, not a crash', (
    tester,
  ) async {
    final log = HardwareCalls();
    await _pump(
      tester,
      healthyPhone(log, ar: FakeAr(log, error: StateError('boom'))),
    );
    await _runToEnd(tester);

    expect(_outcome(tester, SelfTestItem.arPlane), 'Fail');
    expect(_outcome(tester, SelfTestItem.depth), 'Fail');
    expect(tester.takeException(), isNull);
  });

  testWidgets('is served at /self-test, its own route', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: almanacLightTheme(),
          routerConfig: buildRouter(initialLocation: '/self-test'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SelfTestScreen), findsOneWidget);
    expect(find.text('Device self-test'), findsOneWidget);
  });

  testWidgets('is reachable from the Profile tab, so a phone build that '
      'opens on Home can get to it', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: almanacLightTheme(),
          routerConfig: buildRouter(initialLocation: '/profile'),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Device self-test'));
    await tester.pumpAndSettle();

    expect(find.byType(SelfTestScreen), findsOneWidget);
  });
}
