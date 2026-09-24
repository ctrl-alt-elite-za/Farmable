/// Stand-ins for the phone's hardware, so the self-test can be driven through
/// every answer a real phone can give — including the ones an emulator gives.
library;

import 'dart:async';

import 'package:almanac/data/device/ar_probe.dart';
import 'package:almanac/data/device/audio_loopback.dart';
import 'package:almanac/data/device/camera_source.dart';
import 'package:almanac/data/device/location_service.dart';
import 'package:almanac/data/device/object_detector.dart';
import 'package:almanac/data/device/self_test_store.dart';
import 'package:almanac/domain/device/self_test.dart';
import 'package:almanac/features/self_test/self_test_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Counts every call into the hardware. A test that says "nothing is asked
/// for until Run" reads this.
class HardwareCalls {
  final calls = <String>[];

  void add(String call) => calls.add(call);
}

class FakeCamera implements CameraFrameSource {
  final HardwareCalls log;
  final CameraUnavailable? refuse;
  final bool sendFrames;
  final bool hangOnOpen;
  final _frames = StreamController<CameraFrame>.broadcast();
  Timer? _timer;

  FakeCamera(
    this.log, {
    this.refuse,
    this.sendFrames = true,
    this.hangOnOpen = false,
  });

  @override
  bool get isRecorded => false;

  @override
  Stream<CameraFrame> get frames => _frames.stream;

  @override
  Future<void> open() async {
    log.add('camera.open');
    if (refuse != null) throw refuse!;
    if (hangOnOpen) return Completer<void>().future;
    if (!sendFrames) return;
    var i = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      _frames.add(CameraFrame(width: 640, height: 480, index: i++));
    });
  }

  @override
  Widget buildPreview() => const SizedBox(key: Key('fake-preview'));

  @override
  Future<void> close() async {
    log.add('camera.close');
    _timer?.cancel();
    unawaited(_frames.close());
  }
}

class FakeAr implements ArProbe {
  final HardwareCalls log;
  final ArProbeFacts? facts;
  final Object? error;
  final bool hang;

  FakeAr(this.log, {this.facts, this.error, this.hang = false});

  @override
  Future<ArProbeFacts> run(Duration timeout) async {
    log.add('ar.run');
    if (error != null) throw error!;
    if (hang) return Completer<ArProbeFacts>().future;
    return facts!;
  }

  @override
  Future<void> cancel() async => log.add('ar.cancel');
}

class FakeAudio implements AudioLoopback {
  final HardwareCalls log;
  final bool permission;
  final double peak;
  final bool hangOnRecord;
  final Object? error;

  /// When set, recording finishes only when the test completes this —
  /// including after the check has timed out.
  final Completer<void>? releaseRecording;

  FakeAudio(
    this.log, {
    this.permission = true,
    this.peak = -20,
    this.hangOnRecord = false,
    this.error,
    this.releaseRecording,
  });

  @override
  Future<bool> ensurePermission() async {
    log.add('mic.permission');
    if (error != null) throw error!;
    return permission;
  }

  @override
  Future<RecordingTake> record(Duration length) async {
    log.add('mic.record');
    if (hangOnRecord) return Completer<RecordingTake>().future;
    if (releaseRecording != null) {
      await releaseRecording!.future;
    } else {
      await Future<void>.delayed(length);
    }
    return RecordingTake(
      path: '/tmp/take.m4a',
      length: length,
      bytes: 48000,
      peakDbfs: peak,
    );
  }

  @override
  Future<Duration> play(String path) async {
    log.add('mic.play');
    return const Duration(seconds: 3);
  }

  @override
  Future<void> dispose() async => log.add('mic.dispose');
}

class FakeDetector implements ObjectDetectorService {
  final HardwareCalls log;
  final Object? error;
  var _runs = 0;

  FakeDetector(this.log, {this.error});

  @override
  Future<DetectionRun> detectFile(String path) async {
    log.add('detector.run');
    if (error != null) throw error!;
    _runs++;
    return DetectionRun(
      const [
        Detection(label: 'Plant', confidence: .9, box: Rect.zero),
        Detection(label: 'Container', confidence: .8, box: Rect.zero),
      ],
      // Cold first run, then 40, 42, 44 ms: the median of the warm runs is 42.
      Duration(milliseconds: _runs == 1 ? 310 : 38 + 2 * (_runs - 1)),
    );
  }

  @override
  Future<void> close() async => log.add('detector.close');
}

class FakeLocation implements LocationService {
  final HardwareCalls log;
  final LocationUnavailable? refuse;

  FakeLocation(this.log, {this.refuse});

  @override
  Future<LocationFix> currentFix() async {
    log.add('location.fix');
    if (refuse != null) throw refuse!;
    return const LocationFix(
      latitude: -25.75,
      longitude: 28.19,
      accuracyMetres: 8,
    );
  }
}

class MemoryStore implements SelfTestStore {
  final saved = <SelfTestReport>[];

  @override
  Future<String> save(SelfTestReport report, {LocationFix? location}) async {
    saved.add(report);
    return '/memory/self_test/latest.json';
  }
}

/// A phone where everything works.
SelfTestDevices healthyPhone(
  HardwareCalls log, {
  MemoryStore? store,
  CameraFrameSource Function()? camera,
  ArProbe? ar,
  AudioLoopback Function()? audio,
  ObjectDetectorService Function()? detector,
  LocationService? location,
  Duration permissionTimeout = const Duration(seconds: 90),
}) => SelfTestDevices(
  openCamera: camera ?? () => FakeCamera(log),
  ar:
      ar ??
      FakeAr(
        log,
        facts: const ArProbeFacts(
          arAvailable: true,
          depthAvailable: true,
          planesDetected: 2,
          depthFrames: 4,
          trackingFrames: 30,
        ),
      ),
  openAudio: audio ?? () => FakeAudio(log),
  openDetector: detector ?? () => FakeDetector(log),
  sampleImagePath: () async => '/tmp/sample.jpg',
  location: location ?? FakeLocation(log),
  store: store ?? MemoryStore(),
  identity: () async => const DeviceIdentity(
    platform: 'android',
    model: 'Test Phone',
    appVersion: '1.0.0+1',
  ),
  isIos: false,
  firstFrameTimeout: const Duration(seconds: 2),
  previewHold: const Duration(milliseconds: 300),
  arTimeout: const Duration(seconds: 20),
  recordLength: const Duration(seconds: 3),
  permissionTimeout: permissionTimeout,
);

/// An emulator, or a budget phone: no camera, no ARCore, and no plugin
/// behind the microphone or the detector at all.
SelfTestDevices bareEmulator(HardwareCalls log, {MemoryStore? store}) =>
    healthyPhone(
      log,
      store: store,
      camera: () => FakeCamera(
        log,
        refuse: const CameraUnavailable(
          'This phone reports no camera.',
          unsupported: true,
        ),
      ),
      ar: FakeAr(
        log,
        facts: const ArProbeFacts(
          arAvailable: false,
          reason: 'UNSUPPORTED_DEVICE_NOT_CAPABLE',
        ),
      ),
      audio: () =>
          FakeAudio(log, error: MissingPluginException('no record plugin')),
      detector: () =>
          FakeDetector(log, error: MissingPluginException('no ML Kit')),
      location: FakeLocation(
        log,
        refuse: const LocationUnavailable(
          'This phone could not say whether location is allowed.',
          unsupported: true,
        ),
      ),
    );
