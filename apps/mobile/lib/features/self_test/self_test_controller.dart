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

/// Tells a check whether its result still matters. False once the check has
/// timed out, the run has been cancelled, or the controller disposed — after
/// which the check must not touch hardware or state again.
typedef StillLive = bool Function();

/// What a check returns when it notices it has been abandoned. Never shown:
/// the run that wanted it has already moved on.
const _abandoned = CheckResult.fail('Abandoned.');

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

  /// Why the last run stopped before finishing, when it did.
  String? stoppedReason;

  var _disposed = false;

  // Two counters make every late result harmless. `_run` changes when a run
  // starts, is cancelled, or the controller is disposed; `_stage` also changes
  // whenever a check ends, including by timing out. A check captures both
  // when it starts and, after every await, asks whether they still match.
  // Future.timeout stops *waiting* for a check, not the check itself, so this
  // is what stops a timed-out recording from starting playback later.
  var _run = 0;
  var _stage = 0;

  // The hardware a check has open right now, so a timeout, a cancel or
  // dispose can release it even while the check itself is stuck.
  CameraFrameSource? _openCamera;
  AudioLoopback? _openAudio;
  ObjectDetectorService? _openDetector;
  var _arRunning = false;

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

  /// One stage: enter its phase, run the check, then invalidate the check and
  /// release whatever hardware it left open — whether it finished, failed or
  /// timed out.
  Future<T> _runStage<T>(
    SelfTestPhase next,
    List<SelfTestItem> items,
    Future<T> Function(StillLive live) body,
  ) async {
    _enter(next, items);
    final run = _run;
    final stage = ++_stage;
    bool live() => !_disposed && _run == run && _stage == stage;
    try {
      return await body(live);
    } finally {
      if (_stage == stage) _stage++;
      await _releaseHardware();
    }
  }

  Future<void> run() async {
    if (isRunning || _disposed) return;
    final run = ++_run;
    bool stale() => _disposed || _run != run;
    results.clear();
    report = null;
    savedPath = null;
    saveProblem = null;
    stoppedReason = null;
    fix = null;
    final startedAt = now();

    final cameraResult = await _runStage(
      SelfTestPhase.camera,
      [SelfTestItem.camera],
      (live) => runGuarded(
        () => _checkCamera(live),
        timeout: devices.permissionTimeout,
      ),
    );
    if (stale()) return;
    results[SelfTestItem.camera] = cameraResult;

    final ar = await _runStage(SelfTestPhase.ar, [
      SelfTestItem.arPlane,
      SelfTestItem.depth,
    ], _checkAr);
    if (stale()) return;
    results[SelfTestItem.depth] = ar.depth;
    results[SelfTestItem.arPlane] = ar.arPlane;

    final micResult = await _runStage(
      SelfTestPhase.recording,
      [SelfTestItem.microphone],
      (live) => runGuarded(
        () => _checkMicrophone(live),
        timeout: devices.permissionTimeout,
      ),
    );
    if (stale()) return;
    results[SelfTestItem.microphone] = micResult;

    int? detectorMs;
    final detectorResult = await _runStage(
      SelfTestPhase.detector,
      [SelfTestItem.detector],
      (live) => runGuarded(() async {
        final (result, ms) = await _checkDetector(live);
        if (live()) detectorMs = ms;
        return result;
      }),
    );
    if (stale()) return;
    results[SelfTestItem.detector] = detectorResult;

    final locationResult = await _runStage(
      SelfTestPhase.location,
      [SelfTestItem.location],
      (live) => runGuarded(
        () => _checkLocation(live),
        timeout: devices.permissionTimeout,
      ),
    );
    if (stale()) return;
    results[SelfTestItem.location] = locationResult;

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
    if (stale()) return;
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
      final path = await devices.store.save(finished, location: fix);
      if (stale()) return;
      savedPath = path;
    } catch (error) {
      if (stale()) return;
      saveProblem = 'Could not save the report on this phone: $error';
    }
    _enter(SelfTestPhase.done);
  }

  /// Stops a run part-way — the app went to the background. Hardware is
  /// released now, and nothing the abandoned run was waiting on can start
  /// another check, ask for a permission or save a report.
  void cancel(String reason) {
    if (!isRunning) return;
    _run++;
    _stage++;
    unawaited(_releaseHardware());
    stoppedReason = reason;
    report = null;
    _enter(SelfTestPhase.idle);
  }

  /// Releases whatever a check left open. Each handle is taken before it is
  /// released, so a check's own cleanup and a timeout never both close it.
  Future<void> _releaseHardware() async {
    final cam = _openCamera;
    final audio = _openAudio;
    final detector = _openDetector;
    final ar = _arRunning;
    _openCamera = null;
    _openAudio = null;
    _openDetector = null;
    _arRunning = false;
    if (camera != null) {
      camera = null;
      _notify();
    }

    Future<void> quietly(Future<void> Function() release) async {
      try {
        await release().timeout(const Duration(seconds: 5));
      } catch (_) {
        // Best effort: one plugin that will not close must not stop the
        // others from being closed.
      }
    }

    if (cam != null) await quietly(cam.close);
    if (ar) await quietly(devices.ar.cancel);
    if (audio != null) await quietly(audio.dispose);
    if (detector != null) await quietly(detector.close);
  }

  Future<CheckResult> _checkCamera(StillLive live) async {
    final source = devices.openCamera();
    _openCamera = source;
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
      if (!live()) return _abandoned;
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
      if (!live()) return _abandoned;
      // Long enough for a person to see the preview is live, and for a
      // frame rate to mean something.
      final watch = Stopwatch()..start();
      final before = count;
      await Future<void>.delayed(devices.previewHold);
      if (!live()) return _abandoned;
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
      // Released here, before AR starts: only one client can hold the camera.
      if (identical(_openCamera, source)) await _releaseHardware();
    }
  }

  Future<({CheckResult arPlane, CheckResult depth})> _checkAr(
    StillLive live,
  ) async {
    final timeout = devices.arTimeout;
    _arRunning = true;
    try {
      final facts = await devices.ar
          .run(timeout)
          .timeout(timeout + const Duration(seconds: 30));
      _arRunning = false;
      return interpretArProbe(facts, isIos: devices.isIos, timeout: timeout);
    } on MissingPluginException {
      _arRunning = false;
      const none = CheckResult.unsupported(
        'This build has no AR support on this platform.',
      );
      return (arPlane: none, depth: none);
    } on TimeoutException {
      // Still flagged as running, so the stage's release cancels the native
      // session rather than leaving it holding the camera.
      const stuck = CheckResult.fail('The AR session did not finish.');
      return (arPlane: stuck, depth: stuck);
    } catch (error) {
      _arRunning = false;
      final failed = CheckResult.fail('The AR check stopped: $error');
      return (arPlane: failed, depth: failed);
    }
  }

  Future<CheckResult> _checkMicrophone(StillLive live) async {
    final audio = devices.openAudio();
    _openAudio = audio;
    try {
      if (!await audio.ensurePermission()) {
        return const CheckResult.fail(
          'Microphone permission was refused. Allow it in Settings to talk '
          'to the assistant.',
        );
      }
      if (!live()) return _abandoned;
      _enter(SelfTestPhase.recording, [SelfTestItem.microphone]);
      final take = await audio.record(devices.recordLength);
      // A recording that finishes after its check timed out, or after the
      // run was stopped, must not start playback or move the phase.
      if (!live()) return _abandoned;
      final seconds = (take.length.inMilliseconds / 1000).toStringAsFixed(1);
      if (take.bytes < 1024) {
        return CheckResult.fail(
          'Recorded for $seconds s but the file came out empty.',
        );
      }
      _enter(SelfTestPhase.playing, [SelfTestItem.microphone]);
      await audio.play(take.path);
      if (!live()) return _abandoned;
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
      if (identical(_openAudio, audio)) await _releaseHardware();
    }
  }

  Future<(CheckResult, int?)> _checkDetector(StillLive live) async {
    final path = await devices.sampleImagePath();
    if (!live()) return (_abandoned, null);
    final detector = devices.openDetector();
    _openDetector = detector;
    try {
      // The first run loads the model; the ones after it are what a camera
      // screen pays per frame. Report the median of three warm runs.
      final cold = await detector.detectFile(path);
      final warm = <int>[];
      for (var i = 0; i < 3; i++) {
        if (!live()) return (_abandoned, null);
        warm.add((await detector.detectFile(path)).elapsed.inMilliseconds);
      }
      warm.sort();
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
      if (identical(_openDetector, detector)) await _releaseHardware();
    }
  }

  Future<CheckResult> _checkLocation(StillLive live) async {
    try {
      final found = await devices.location.currentFix();
      if (!live()) return _abandoned;
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

  /// Leaving the screen disposes the controller, which stops the run the
  /// same way [cancel] does: no later check, prompt, recording or save.
  @override
  void dispose() {
    _disposed = true;
    _run++;
    _stage++;
    unawaited(_releaseHardware());
    super.dispose();
  }
}
