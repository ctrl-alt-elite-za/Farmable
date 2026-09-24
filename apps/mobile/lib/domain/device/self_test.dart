/// The device self-test: what it checks, what each check can conclude, and
/// the report it produces.
///
/// Pure Dart. Nothing here touches a plugin, which is what lets the runner's
/// promises — every check ends, nothing throws out of it, "not supported" is
/// an answer rather than a crash — be proved in a unit test with fakes.
library;

import 'dart:async';

import 'package:flutter/services.dart' show MissingPluginException;

/// What a single check concluded.
///
/// [unsupported] is a valid, passing-grade answer: a phone without LiDAR has
/// no depth sensor to test, and saying so is the correct result, not a fault.
enum CheckOutcome {
  pass('pass'),
  fail('fail'),
  unsupported('unsupported');

  /// The spelling `docs/api/devices-self-test.md` fixes for the upload.
  final String wire;

  const CheckOutcome(this.wire);
}

/// The things the self-test checks, in the order it runs them.
///
/// The order matters. Camera runs first because it is what asks for the
/// camera permission, and the AR checks need that permission to open the
/// camera themselves. The camera preview is released before AR starts, since
/// only one client can hold the camera at a time.
enum SelfTestItem {
  camera('Camera preview', 'camera_preview'),
  depth('Depth sensor', 'lidar_depth'),
  arPlane('AR surface detection', 'ar_plane'),
  microphone('Microphone record and playback', 'mic_record'),
  detector('Detector timing', null),
  location('Location', null);

  final String label;

  /// The report field this item fills, or null when the upload contract has
  /// no field for it (detector timing is carried as `detector_ms`; location
  /// is local-only).
  final String? wireField;

  const SelfTestItem(this.label, this.wireField);
}

class CheckResult {
  final CheckOutcome outcome;

  /// One plain sentence a person can act on. Always present — a bare "Fail"
  /// with no reason is not evidence of anything.
  final String detail;

  const CheckResult(this.outcome, this.detail);

  const CheckResult.pass(this.detail) : outcome = CheckOutcome.pass;
  const CheckResult.fail(this.detail) : outcome = CheckOutcome.fail;
  const CheckResult.unsupported(this.detail)
    : outcome = CheckOutcome.unsupported;

  @override
  String toString() => '${outcome.wire}: $detail';
}

/// A check, and the only way the runner knows how to run one.
typedef CheckBody = Future<CheckResult> Function();

/// Runs one check so that it cannot hang the screen or crash the app.
///
/// * A [MissingPluginException] means the platform has no implementation at
///   all — a desktop build, a test, an emulator image without the service.
///   That is "not supported", never a failure.
/// * Any other exception is a failure carrying its message.
/// * A check that never returns is a failure after [timeout].
Future<CheckResult> runGuarded(
  CheckBody body, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  try {
    return await body().timeout(timeout);
  } on TimeoutException {
    return CheckResult.fail(
      'Did not finish within ${timeout.inSeconds} seconds.',
    );
  } on MissingPluginException {
    return const CheckResult.unsupported(
      'This phone has no support for this check.',
    );
  } catch (error) {
    return CheckResult.fail('Stopped with an error: $error');
  }
}

/// Everything a finished run knows, in the shape `docs/api/devices-self-test.md`
/// fixes for `POST /devices/self-test`.
class SelfTestReport {
  final String platform;
  final String appVersion;
  final String buildSha;
  final String deviceModel;
  final DateTime startedAt;
  final Map<SelfTestItem, CheckResult> results;

  /// The warm detector run, in milliseconds. Null when the detector did not
  /// run — reported as null rather than as a made-up number.
  final int? detectorMs;

  const SelfTestReport({
    required this.platform,
    required this.appVersion,
    required this.buildSha,
    required this.deviceModel,
    required this.startedAt,
    required this.results,
    required this.detectorMs,
  });

  /// Fails if anything failed. "Not supported" does not fail a phone: a
  /// phone without LiDAR is not a broken phone.
  CheckOutcome get overall =>
      results.values.any((r) => r.outcome == CheckOutcome.fail)
      ? CheckOutcome.fail
      : CheckOutcome.pass;

  String _wire(SelfTestItem item) =>
      (results[item] ?? const CheckResult.fail('Did not run.')).outcome.wire;

  /// The upload body. Field names and spellings are the contract's.
  ///
  /// `notes` holds one `"<field>: <why>"` line per item that did not pass,
  /// including the items the contract has no field for, so nothing the
  /// person saw on screen is missing from the report.
  Map<String, Object?> toJson() => {
    'platform': platform,
    'app_version': appVersion,
    'build_sha': buildSha,
    'device_model': deviceModel,
    'detector_ms': detectorMs,
    'started_at': startedAt.toUtc().toIso8601String(),
    'camera_preview': _wire(SelfTestItem.camera),
    'lidar_depth': _wire(SelfTestItem.depth),
    'ar_plane': _wire(SelfTestItem.arPlane),
    'mic_record': _wire(SelfTestItem.microphone),
    'notes': [
      for (final item in SelfTestItem.values)
        if (results[item] case final r? when r.outcome != CheckOutcome.pass)
          '${item.wireField ?? item.name}: ${r.detail}',
    ],
    'overall': overall.wire,
  };
}
