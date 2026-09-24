/// The self-test's pure parts: the guard every check runs inside, the reading
/// of AR facts, and the report's wire shape.
library;

import 'dart:async';

import 'package:almanac/data/device/ar_probe.dart';
import 'package:almanac/domain/device/self_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('runGuarded', () {
    test('passes a result straight through', () async {
      final r = await runGuarded(() async => const CheckResult.pass('ok'));
      expect(r.outcome, CheckOutcome.pass);
    });

    test('a missing plugin is "not supported", not a failure', () async {
      final r = await runGuarded(
        () async => throw MissingPluginException('none'),
      );
      expect(r.outcome, CheckOutcome.unsupported);
    });

    test('any other exception is a failure that says what it was', () async {
      final r = await runGuarded(() async => throw StateError('camera gone'));
      expect(r.outcome, CheckOutcome.fail);
      expect(r.detail, contains('camera gone'));
    });

    test('a check that never ends fails on its timeout', () async {
      final r = await runGuarded(
        () => Completer<CheckResult>().future,
        timeout: const Duration(milliseconds: 20),
      );
      expect(r.outcome, CheckOutcome.fail);
      expect(r.detail, contains('Did not finish'));
    });
  });

  group('interpretArProbe', () {
    const t = Duration(seconds: 20);

    test('no ARCore/ARKit: both not supported', () {
      final r = interpretArProbe(
        const ArProbeFacts(arAvailable: false, reason: 'UNSUPPORTED'),
        isIos: false,
        timeout: t,
      );
      expect(r.arPlane.outcome, CheckOutcome.unsupported);
      expect(r.depth.outcome, CheckOutcome.unsupported);
    });

    test('iPhone without LiDAR: AR passes, depth not supported', () {
      final r = interpretArProbe(
        const ArProbeFacts(
          arAvailable: true,
          planesDetected: 3,
          trackingFrames: 40,
        ),
        isIos: true,
        timeout: t,
      );
      expect(r.arPlane.outcome, CheckOutcome.pass);
      expect(r.depth.outcome, CheckOutcome.unsupported);
      expect(r.depth.detail, contains('LiDAR'));
    });

    test('LiDAR phone that delivered depth: both pass', () {
      final r = interpretArProbe(
        const ArProbeFacts(
          arAvailable: true,
          depthAvailable: true,
          planesDetected: 1,
          depthFrames: 9,
          trackingFrames: 40,
        ),
        isIos: true,
        timeout: t,
      );
      expect(r.arPlane.outcome, CheckOutcome.pass);
      expect(r.depth.outcome, CheckOutcome.pass);
    });

    test('ARCore supported but not installed: fail, and says to install', () {
      final r = interpretArProbe(
        const ArProbeFacts(arAvailable: true, arInstalled: false),
        isIos: false,
        timeout: t,
      );
      expect(r.arPlane.outcome, CheckOutcome.fail);
      expect(r.arPlane.detail, contains('Play Store'));
    });

    test('tracked but found no surface: fail, and says what to do', () {
      final r = interpretArProbe(
        const ArProbeFacts(arAvailable: true, trackingFrames: 200),
        isIos: false,
        timeout: t,
      );
      expect(r.arPlane.outcome, CheckOutcome.fail);
      expect(r.arPlane.detail, contains('Point the phone'));
    });

    test('depth source present but silent: depth fails', () {
      final r = interpretArProbe(
        const ArProbeFacts(
          arAvailable: true,
          depthAvailable: true,
          planesDetected: 1,
          trackingFrames: 10,
        ),
        isIos: false,
        timeout: t,
      );
      expect(r.depth.outcome, CheckOutcome.fail);
    });

    test('reads the platform map, tolerating missing keys', () {
      final f = ArProbeFacts.fromMap({
        'arAvailable': true,
        'planesDetected': 2,
      });
      expect(f.arAvailable, isTrue);
      expect(f.arInstalled, isTrue);
      expect(f.cameraPermission, isTrue);
      expect(f.planesDetected, 2);
      expect(f.depthAvailable, isFalse);
    });
  });

  group('SelfTestReport.toJson', () {
    SelfTestReport report(Map<SelfTestItem, CheckResult> results) =>
        SelfTestReport(
          platform: 'ios',
          appVersion: '1.0.0+1',
          buildSha: 'abc1234',
          deviceModel: 'iPhone 12 Pro (iPhone13,3)',
          startedAt: DateTime.utc(2026, 9, 17, 8),
          results: results,
          detectorMs: 12,
        );

    test('has exactly the fields docs/api/devices-self-test.md fixes', () {
      final json = report({
        for (final i in SelfTestItem.values) i: const CheckResult.pass('ok'),
      }).toJson();
      expect(json.keys.toSet(), {
        'platform',
        'app_version',
        'build_sha',
        'device_model',
        'detector_ms',
        'started_at',
        'camera_preview',
        'lidar_depth',
        'ar_plane',
        'mic_record',
        'notes',
        'overall',
      });
      expect(json['started_at'], '2026-09-17T08:00:00.000Z');
      expect(json['overall'], 'pass');
      expect(json['notes'], isEmpty);
    });

    test('one "<field>: <why>" note per item that did not pass', () {
      final json = report({
        SelfTestItem.camera: const CheckResult.pass('ok'),
        SelfTestItem.depth: const CheckResult.unsupported('no LiDAR'),
        SelfTestItem.arPlane: const CheckResult.pass('ok'),
        SelfTestItem.microphone: const CheckResult.fail('refused'),
        SelfTestItem.detector: const CheckResult.pass('ok'),
        SelfTestItem.location: const CheckResult.pass('ok'),
      }).toJson();
      expect(json['lidar_depth'], 'unsupported');
      expect(json['mic_record'], 'fail');
      expect(json['notes'], ['lidar_depth: no LiDAR', 'mic_record: refused']);
      expect(json['overall'], 'fail');
    });

    test('"not supported" alone does not fail a phone', () {
      final json = report({
        for (final i in SelfTestItem.values)
          i: const CheckResult.unsupported('absent'),
      }).toJson();
      expect(json['overall'], 'pass');
    });
  });
}
