/// AR surface detection and depth, asked of the platform directly.
///
/// There is no maintained Flutter plugin that does this on both platforms, so
/// it is a small method channel implemented in the app itself:
/// `ios/Runner/AppDelegate.swift` (ARKit, LiDAR scene depth) and
/// `android/app/src/main/kotlin/.../DeviceProbe.kt` (ARCore planes and the
/// ARCore Depth API). Each runs one short AR session with no view, reports
/// what it saw, and tears the session down.
///
/// The native side reports raw facts; deciding pass, fail or "not supported"
/// happens here, in Dart, where it can be tested.
library;

import 'package:flutter/services.dart';

import '../../domain/device/self_test.dart';

class ArProbeFacts {
  /// The platform has AR at all: ARKit world tracking, or ARCore on a
  /// supported device.
  final bool arAvailable;

  /// Android only: Google Play Services for AR is installed and current.
  final bool arInstalled;

  final bool cameraPermission;

  /// A depth source exists: LiDAR on iOS, the ARCore Depth API on Android.
  final bool depthAvailable;

  final int planesDetected;
  final int depthFrames;
  final int trackingFrames;

  /// Why AR is unavailable, in the platform's words.
  final String? reason;

  /// The session stopped with an error.
  final String? error;

  const ArProbeFacts({
    this.arAvailable = false,
    this.arInstalled = true,
    this.cameraPermission = true,
    this.depthAvailable = false,
    this.planesDetected = 0,
    this.depthFrames = 0,
    this.trackingFrames = 0,
    this.reason,
    this.error,
  });

  factory ArProbeFacts.fromMap(Map<Object?, Object?> m) => ArProbeFacts(
    arAvailable: m['arAvailable'] == true,
    arInstalled: m['arInstalled'] != false,
    cameraPermission: m['cameraPermission'] != false,
    depthAvailable: m['depthAvailable'] == true,
    planesDetected: (m['planesDetected'] as num?)?.toInt() ?? 0,
    depthFrames: (m['depthFrames'] as num?)?.toInt() ?? 0,
    trackingFrames: (m['trackingFrames'] as num?)?.toInt() ?? 0,
    reason: m['reason'] as String?,
    error: m['error'] as String?,
  );
}

abstract interface class ArProbe {
  /// Runs one AR session for at most [timeout], returning early once a
  /// surface (and, where there is a depth source, a depth frame) has been
  /// seen.
  Future<ArProbeFacts> run(Duration timeout);

  /// Ends a running session early and releases the camera — the screen was
  /// left, the app went to the background, or [run] timed out. A no-op when
  /// nothing is running.
  Future<void> cancel();
}

class NativeArProbe implements ArProbe {
  static const channel = MethodChannel('za.co.almanac.app/device_probe');

  const NativeArProbe();

  @override
  Future<ArProbeFacts> run(Duration timeout) async {
    final facts = await channel.invokeMapMethod<Object?, Object?>('arProbe', {
      'timeoutMs': timeout.inMilliseconds,
    });
    return ArProbeFacts.fromMap(facts ?? const {});
  }

  @override
  Future<void> cancel() async {
    try {
      await channel.invokeMethod<void>('arCancel');
    } on MissingPluginException {
      // Nothing to cancel on a platform with no probe.
    }
  }
}

/// Turns one probe's facts into the two self-test answers.
({CheckResult arPlane, CheckResult depth}) interpretArProbe(
  ArProbeFacts f, {
  required bool isIos,
  required Duration timeout,
}) {
  final noDepth = isIos
      ? 'This phone has no LiDAR depth sensor.'
      : 'ARCore reports no depth support on this phone.';

  if (!f.arAvailable) {
    final why = f.reason == null ? '' : ' (${f.reason})';
    return (
      arPlane: CheckResult.unsupported(
        isIos
            ? 'This phone does not support ARKit world tracking$why.'
            : 'This phone is not on the ARCore supported list$why.',
      ),
      depth: CheckResult.unsupported(noDepth),
    );
  }
  if (!f.arInstalled) {
    const install =
        'Google Play Services for AR is missing or out of date. Install '
        'it from the Play Store and run the test again.';
    return (
      arPlane: const CheckResult.fail(install),
      depth: const CheckResult.fail(install),
    );
  }
  if (!f.cameraPermission) {
    const denied =
        'AR needs the camera, and camera permission was refused. Allow it '
        'in Settings and run the test again.';
    return (
      arPlane: const CheckResult.fail(denied),
      depth: f.depthAvailable
          ? const CheckResult.fail(denied)
          : CheckResult.unsupported(noDepth),
    );
  }

  final seconds = timeout.inSeconds;
  final CheckResult arPlane;
  if (f.planesDetected > 0) {
    arPlane = CheckResult.pass(
      f.planesDetected == 1
          ? 'Found 1 surface.'
          : 'Found ${f.planesDetected} surfaces.',
    );
  } else if (f.error != null) {
    arPlane = CheckResult.fail('The AR session stopped: ${f.error}');
  } else if (f.trackingFrames == 0) {
    arPlane = CheckResult.fail(
      'AR tracking never started in $seconds seconds. Try again in better '
      'light.',
    );
  } else {
    arPlane = CheckResult.fail(
      'No surface found in $seconds seconds. Point the phone at the floor '
      'or ground and move it slowly.',
    );
  }

  final CheckResult depth;
  if (!f.depthAvailable) {
    depth = CheckResult.unsupported(noDepth);
  } else if (f.depthFrames > 0) {
    depth = CheckResult.pass(
      isIos ? 'LiDAR depth frames received.' : 'ARCore depth frames received.',
    );
  } else if (f.error != null) {
    depth = CheckResult.fail('The AR session stopped: ${f.error}');
  } else {
    depth = CheckResult.fail(
      'The phone has a depth source but sent no depth frame in $seconds '
      'seconds.',
    );
  }
  return (arPlane: arPlane, depth: depth);
}
