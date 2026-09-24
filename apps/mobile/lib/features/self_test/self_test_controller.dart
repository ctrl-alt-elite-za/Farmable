/// Runs the device self-test, one check after another, and holds what the
/// screen draws.
///
/// Every device dependency comes in through [SelfTestDevices], so a widget
/// test can run the whole sequence — including a camera that refuses, an AR
/// service that is missing and a microphone that hangs — without a phone.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../app/config.dart';
import '../../data/device/ar_probe.dart';
import '../../data/device/audio_loopback.dart';
import '../../data/device/camera_source.dart';
import '../../data/device/location_service.dart';
import '../../data/device/object_detector.dart';
import '../../data/device/self_test_store.dart';
import '../../domain/device/self_test.dart';

/// Everything the self-test touches on the phone.
class SelfTestDevices {
  final CameraFrameSource Function() openCamera;
  final ArProbe ar;
  final AudioLoopback Function() openAudio;
  final ObjectDetectorService Function() openDetector;
  final Future<String> Function() sampleImagePath;
  final LocationService location;
  final SelfTestStore store;
  final Future<DeviceIdentity> Function() identity;
  final bool isIos;

  final Duration firstFrameTimeout;
  final Duration previewHold;
  final Duration arTimeout;
  final Duration recordLength;

  /// Long enough for a person to read and answer a permission prompt. The
  /// prompt blocks the plugin call until they do.
  final Duration permissionTimeout;

  const SelfTestDevices({
    required this.openCamera,
    required this.ar,
    required this.openAudio,
    required this.openDetector,
    required this.sampleImagePath,
    required this.location,
    required this.store,
    required this.identity,
    required this.isIos,
    this.firstFrameTimeout = const Duration(seconds: 8),
    this.previewHold = const Duration(seconds: 2),
    this.arTimeout = const Duration(seconds: 20),
    this.recordLength = const Duration(seconds: 3),
    this.permissionTimeout = const Duration(seconds: 90),
  });

  factory SelfTestDevices.onDevice() => SelfTestDevices(
    openCamera: defaultCameraSource,
    ar: const NativeArProbe(),
    openAudio: DeviceAudioLoopback.new,
    openDetector: MlKitObjectDetectorService.new,
    sampleImagePath: materializeSampleImage,
    location: const GeolocatorLocationService(),
    store: FileSelfTestStore(),
    identity: readDeviceIdentity,
    isIos: Platform.isIOS,
  );
}

/// What the screen should be showing besides the results.
enum SelfTestPhase {
  idle,
  camera,
  ar,
  recording,
  playing,
  detector,
  location,
  saving,
  done,
}

class SelfTestController extends ChangeNotifier {
  final SelfTestDevices devices;
  final DateTime Function() now;

  SelfTestController(this.devices, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  final results = <SelfTestItem, CheckResult>{};
  final active = <SelfTestItem>{};
  SelfTestPhase phase = SelfTestPhase.idle;

  /// Set while the camera check is showing a preview.
  CameraFrameSource? camera;

  LocationFix? fix;
  SelfTestReport? report;

  /// Where the report was written, or why it could not be.
  String? savedPath;
  String? saveProblem;

  var _disposed = false;

  bool get isRunning =>
      phase != SelfTestPhase.idle && phase != SelfTestPhase.done;

  void _enter(SelfTestPhase next, [Iterable<SelfTestItem> items = const []]) {
    phase = next;
    active
      ..clear()
      ..addAll(items);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> run() async {
    if (isRunning) return;
    results.clear();
    report = null;
    savedPath = null;
    saveProblem = null;
    fix = null;
    final startedAt = now();

    _enter(SelfTestPhase.camera, [SelfTestItem.camera]);
    results[SelfTestItem.camera] = await runGuarded(
      _checkCamera,
      timeout: devices.permissionTimeout,
    );

    _enter(SelfTestPhase.ar, [SelfTestItem.arPlane, SelfTestItem.depth]);
    final ar = await _checkAr();
    results[SelfTestItem.depth] = ar.depth;
    results[SelfTestItem.arPlane] = ar.arPlane;

    _enter(SelfTestPhase.recording, [SelfTestItem.microphone]);
    results[SelfTestItem.microphone] = await runGuarded(
      _checkMicrophone,
      timeout: devices.permissionTimeout,
    );

    _enter(SelfTestPhase.detector, [SelfTestItem.detector]);
    int? detectorMs;
    results[SelfTestItem.detector] = await runGuarded(() async {
      final (result, ms) = await _checkDetector();
      detectorMs = ms;
      return result;
    });

    _enter(SelfTestPhase.location, [SelfTestItem.location]);
    results[SelfTestItem.location] = await runGuarded(
      _checkLocation,
      timeout: devices.permissionTimeout,
    );

    _enter(SelfTestPhase.saving);
    DeviceIdentity identity;
    try {
      identity = await devices.identity();
    } catch (_) {
      // A report with an unknown phone is still a report.
      identity = DeviceIdentity(
        platform: devices.isIos ? 'ios' : 'android',
        model: 'unknown',
        appVersion: 'unknown',
      );
    }
    final finished = SelfTestReport(
      platform: identity.platform,
      appVersion: identity.appVersion,
      buildSha: buildSha,
      deviceModel: identity.model,
      startedAt: startedAt,
      results: Map.of(results),
      detectorMs: detectorMs,
    );
    report = finished;
    try {
      savedPath = await devices.store.save(finished, location: fix);
    } catch (error) {
      saveProblem = 'Could not save the report on this phone: $error';
    }
    _enter(SelfTestPhase.done);
  }

  Future<CheckResult> _checkCamera() async {
    final source = devices.openCamera();
    final firstFrame = Completer<CameraFrame>();
    var count = 0;
    // Listen before opening: a recorded source emits its first frame inside
    // open(), and a broadcast stream does not replay it.
    final sub = source.frames.listen((frame) {
      count++;
      if (!firstFrame.isCompleted) firstFrame.complete(frame);
    });
    try {
      await source.open();
      camera = source;
      _notify();
      final CameraFrame first;
      try {
        first = await firstFrame.future.timeout(devices.firstFrameTimeout);
      } on TimeoutException {
        return CheckResult.fail(
          'The camera opened but sent no picture in '
          '${devices.firstFrameTimeout.inSeconds} seconds.',
        );
      }
      // Long enough for a person to see the preview is live, and for a
      // frame rate to mean something.
      final watch = Stopwatch()..start();
      final before = count;
      await Future<void>.delayed(devices.previewHold);
      final seconds = watch.elapsedMilliseconds / 1000;
      final fps = seconds == 0 ? 0 : ((count - before) / seconds).round();
      final size = '${first.width}×${first.height}';
      return CheckResult.pass(
        source.isRecorded
            ? 'Test mode: recorded frames ($size), not the live camera.'
            : 'Live preview at $size, about $fps frames a second.',
      );
    } on CameraUnavailable catch (e) {
      return e.unsupported
          ? CheckResult.unsupported(e.reason)
          : CheckResult.fail(e.reason);
    } finally {
      // Not awaited: nothing depends on the cancel settling, and a broadcast
      // subscription's cancel can outlive the check it belonged to.
      unawaited(sub.cancel());
      camera = null;
      _notify();
      // Released before AR starts: only one client can hold the camera.
      await source.close();
    }
  }

  Future<({CheckResult arPlane, CheckResult depth})> _checkAr() async {
    final timeout = devices.arTimeout;
    try {
      final facts = await devices.ar
          .run(timeout)
          .timeout(timeout + const Duration(seconds: 30));
      return interpretArProbe(facts, isIos: devices.isIos, timeout: timeout);
    } on MissingPluginException {
      const none = CheckResult.unsupported(
        'This build has no AR support on this platform.',
      );
      return (arPlane: none, depth: none);
    } on TimeoutException {
      const stuck = CheckResult.fail('The AR session did not finish.');
      return (arPlane: stuck, depth: stuck);
    } catch (error) {
      final failed = CheckResult.fail('The AR check stopped: $error');
      return (arPlane: failed, depth: failed);
    }
  }

  Future<CheckResult> _checkMicrophone() async {
    final audio = devices.openAudio();
    try {
      if (!await audio.ensurePermission()) {
        return const CheckResult.fail(
          'Microphone permission was refused. Allow it in Settings to talk '
          'to the assistant.',
        );
      }
      _enter(SelfTestPhase.recording, [SelfTestItem.microphone]);
      final take = await audio.record(devices.recordLength);
      final seconds = (take.length.inMilliseconds / 1000).toStringAsFixed(1);
      if (take.bytes < 1024) {
        return CheckResult.fail(
          'Recorded for $seconds s but the file came out empty.',
        );
      }
      _enter(SelfTestPhase.playing, [SelfTestItem.microphone]);
      await audio.play(take.path);
      // Played back either way, so the person hears what was captured — but
      // a take with no sound in it is not a working microphone.
      if (take.peakDbfs <= -90) {
        return CheckResult.fail(
          'Recorded $seconds s and played it back, but it was silent. '
          'Check nothing covers the microphone.',
        );
      }
      return CheckResult.pass(
        'Recorded $seconds s (loudest ${take.peakDbfs.round()} dBFS) and '
        'played it back.',
      );
    } finally {
      await audio.dispose();
    }
  }

  Future<(CheckResult, int?)> _checkDetector() async {
    final path = await devices.sampleImagePath();
    final detector = devices.openDetector();
    try {
      // The first run loads the model; the ones after it are what a camera
      // screen pays per frame. Report the median of three warm runs.
      final cold = await detector.detectFile(path);
      final warm = [
        for (var i = 0; i < 3; i++)
          (await detector.detectFile(path)).elapsed.inMilliseconds,
      ]..sort();
      final ms = warm[1];
      final found = cold.detections.length;
      return (
        CheckResult.pass(
          'First run ${cold.elapsed.inMilliseconds} ms, then $ms ms. '
          'Found $found ${found == 1 ? 'object' : 'objects'} in the sample '
          'picture.',
        ),
        ms,
      );
    } finally {
      await detector.close();
    }
  }

  Future<CheckResult> _checkLocation() async {
    try {
      final found = await devices.location.currentFix();
      fix = found;
      return CheckResult.pass(
        'Found this phone to within ${found.accuracyMetres.round()} m.',
      );
    } on LocationUnavailable catch (e) {
      return e.unsupported
          ? CheckResult.unsupported(e.reason)
          : CheckResult.fail(e.reason);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final open = camera;
    camera = null;
    if (open != null) unawaited(open.close());
    super.dispose();
  }
}
