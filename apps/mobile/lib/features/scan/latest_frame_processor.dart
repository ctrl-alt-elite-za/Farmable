import 'dart:async';

/// Processes one frame and retains only the newest arrival while busy.
///
/// A camera/native adapter can feed buffer handles through [submit]. Old frames
/// are overwritten rather than queued, keeping camera-to-overlay latency bounded.
class LatestFrameProcessor<T> {
  final Future<void> Function(T frame) process;
  T? _latest;
  bool _busy = false;
  bool _disposed = false;

  LatestFrameProcessor(this.process);

  void submit(T frame) {
    if (_disposed) return;
    _latest = frame;
    if (!_busy) unawaited(_drain());
  }

  Future<void> _drain() async {
    _busy = true;
    while (!_disposed && _latest != null) {
      final frame = _latest as T;
      _latest = null;
      await process(frame);
    }
    _busy = false;
  }

  void dispose() {
    _disposed = true;
    _latest = null;
  }
}
