import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../app/config.dart';
import '../../data/device/camera_source.dart';
import '../../domain/vision/crop_detection.dart';
import '../../domain/vision/crop_frame_processor.dart';

enum CropScanPhase { idle, opening, playing, stopped, unavailable, failed }

/// Test replay only until #16 supplies approved artifacts and native adapters.
/// No live camera or generic ML Kit detector is substituted for the crop model.
class CropScanController extends ChangeNotifier {
  final bool replayEnabled;
  final RecordedCameraSource Function() _createSource;
  final _watch = Stopwatch()..start();
  final Duration Function()? clock;
  Duration get _now => clock?.call() ?? _watch.elapsed;
  RecordedCameraSource? source;
  StreamSubscription<CameraFrame>? _subscription;
  CropFrameProcessor? _processor;
  CropFrameResult? result;
  Size imageSize = const Size(480, 360);
  late CropScanPhase phase = replayEnabled
      ? CropScanPhase.idle
      : CropScanPhase.unavailable;
  String? failure;
  var _generation = 0;
  var _disposed = false;

  CropScanController({
    bool replay = testMode,
    bool demo = demoMode,
    this.clock,
    RecordedCameraSource Function()? createSource,
  }) : replayEnabled = replay && !demo,
       _createSource =
           createSource ??
           (() =>
               RecordedCameraSource(asset: 'assets/test_mode/crop_scan.json'));

  int get overlayFps => _processor?.overlayFps ?? 0;
  int get droppedFrames => _processor?.droppedFrames ?? 0;

  Future<void> start() async {
    if (_disposed ||
        !replayEnabled ||
        phase == CropScanPhase.opening ||
        phase == CropScanPhase.playing) {
      return;
    }
    final generation = ++_generation;
    phase = CropScanPhase.opening;
    failure = null;
    result = null;
    final processor = _processor = CropFrameProcessor(clock: () => _now);
    notifyListeners();
    try {
      final camera = source = _createSource();
      _subscription = camera.frames.listen((frame) {
        if (_disposed || generation != _generation) return;
        final capturedAt = _now;
        final recorded = List<Detection>.of(camera.currentDetections);
        imageSize = Size(frame.width.toDouble(), frame.height.toDouble());
        unawaited(_process(processor, frame, recorded, capturedAt, generation));
      }, onError: (Object error) => unawaited(_fail(error, generation)));
      await camera.open();
      if (_disposed || generation != _generation) {
        await camera.close();
        return;
      }
      phase = CropScanPhase.playing;
      notifyListeners();
    } catch (error) {
      await _fail(error, generation);
    }
  }

  Future<void> _process(
    CropFrameProcessor processor,
    CameraFrame frame,
    List<Detection> recorded,
    Duration capturedAt,
    int generation,
  ) async {
    try {
      final next = await processor.process(
        capturedAt: capturedAt,
        infer: () async => [
          for (final detection in recorded)
            CropDetection(
              rawLabel: detection.label,
              confidence: detection.confidence,
              checkSuggested: detection.checkSuggested,
              box: Rect.fromLTRB(
                detection.box.left / frame.width,
                detection.box.top / frame.height,
                detection.box.right / frame.width,
                detection.box.bottom / frame.height,
              ),
            ),
        ],
      );
      if (_disposed || generation != _generation || next == null) return;
      result = next;
      notifyListeners();
    } catch (error) {
      await _fail(error, generation);
    }
  }

  void markPresented(CropFrameResult frame) => _processor?.markPresented(frame);

  Future<void> _fail(Object error, int generation) async {
    if (_disposed || generation != _generation) return;
    final cleanup = stop();
    if (_disposed || _generation != generation + 1) {
      await cleanup;
      return;
    }
    phase = CropScanPhase.failed;
    failure = error is CameraUnavailable
        ? error.reason
        : 'The test recording could not be played. Try again.';
    notifyListeners();
    await cleanup;
  }

  Future<void> stop() async {
    ++_generation;
    _processor?.close();
    result = null;
    final subscription = _subscription;
    final camera = source;
    _subscription = null;
    source = null;
    phase = replayEnabled ? CropScanPhase.stopped : CropScanPhase.unavailable;
    if (!_disposed) notifyListeners();
    // Stop emission synchronously before awaiting subscription cleanup. In
    // particular, dispose must not leave a replay timer running for one turn.
    final closing = camera?.close();
    final cancelling = subscription?.cancel();
    await closing;
    await cancelling;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    _watch.stop();
    super.dispose();
  }
}
