import 'crop_detection.dart';

class CropFrameResult {
  final int frameId;
  final Duration capturedAt;
  final Duration completedAt;
  final List<TrackedCrop> crops;
  const CropFrameResult(
    this.frameId,
    this.capturedAt,
    this.completedAt,
    this.crops,
  );
}

/// Admission happens before conversion/inference. There is no waiting queue.
/// The native adapter must perform expensive work outside Flutter's UI isolate.
class CropFrameProcessor {
  final int frameStride;
  final Duration maxResultAge;
  final Duration Function() clock;
  final CropTracker tracker;
  var _busy = false;
  var _closed = false;
  var _seen = 0;
  var droppedFrames = 0;
  Duration? _lastCapture;
  final _presentations = <Duration>[];
  int? _lastPresentedFrame;

  CropFrameProcessor({
    required this.clock,
    this.frameStride = 2,
    this.maxResultAge = const Duration(milliseconds: 150),
    CropTracker? tracker,
  }) : tracker = tracker ?? CropTracker() {
    if ((frameStride != 2 && frameStride != 3) ||
        maxResultAge <= Duration.zero) {
      throw ArgumentError(
        'Use a positive result deadline and a stride of 2 or 3',
      );
    }
  }

  Future<CropFrameResult?> process({
    required Duration capturedAt,
    required Future<List<CropDetection>> Function() infer,
  }) async {
    if (_closed) return null;
    final now = clock();
    if (capturedAt < Duration.zero ||
        capturedAt > now ||
        (_lastCapture != null && capturedAt <= _lastCapture!)) {
      throw ArgumentError(
        'Capture timestamps must increase on the pipeline clock',
      );
    }
    _lastCapture = capturedAt;
    final id = _seen++;
    if (_busy || id % frameStride != 0 || now - capturedAt > maxResultAge) {
      droppedFrames++;
      return null;
    }
    _busy = true;
    try {
      final detections = await infer();
      final completedAt = clock();
      if (_closed || completedAt - capturedAt > maxResultAge) {
        droppedFrames++;
        return null;
      }
      return CropFrameResult(
        id,
        capturedAt,
        completedAt,
        tracker.update(detections, capturedAt),
      );
    } finally {
      _busy = false;
    }
  }

  /// Call after the corresponding overlay is painted, never after inference.
  /// Returns actual camera-to-presentation age for device benchmark samples.
  Duration? markPresented(CropFrameResult result) {
    final now = clock();
    if (_closed ||
        result.completedAt > now ||
        now - result.capturedAt > maxResultAge ||
        (_lastPresentedFrame != null &&
            result.frameId <= _lastPresentedFrame!)) {
      return null;
    }
    _lastPresentedFrame = result.frameId;
    _presentations.add(now);
    _trimPresentations(now);
    return now - result.capturedAt;
  }

  void _trimPresentations(Duration now) => _presentations.removeWhere(
    (time) => now - time >= const Duration(seconds: 1),
  );

  /// Overlay updates actually presented in the trailing second (not camera FPS).
  int get overlayFps {
    _trimPresentations(clock());
    return _presentations.length;
  }

  void close() {
    _closed = true;
    tracker.reset();
    _presentations.clear();
  }
}
