class LatencySummary {
  final double p50Milliseconds;
  final double p95Milliseconds;
  final int samples;

  const LatencySummary({
    required this.p50Milliseconds,
    required this.p95Milliseconds,
    required this.samples,
  });
}

class ScanLatencyMetrics {
  final List<Duration> _cameraToVisible = [];

  void recordFrame({
    required DateTime capturedAt,
    required DateTime inferenceStartedAt,
    required DateTime inferenceEndedAt,
    required DateTime overlayRenderedAt,
  }) {
    if (inferenceStartedAt.isBefore(capturedAt) ||
        inferenceEndedAt.isBefore(inferenceStartedAt) ||
        overlayRenderedAt.isBefore(inferenceEndedAt)) {
      throw ArgumentError('Scan timestamps must be chronological');
    }
    recordCameraToVisible(overlayRenderedAt.difference(capturedAt));
  }

  void recordCameraToVisible(Duration latency) {
    _cameraToVisible.add(latency);
  }

  LatencySummary? get summary {
    if (_cameraToVisible.isEmpty) return null;
    final values =
        _cameraToVisible
            .map((duration) => duration.inMicroseconds / 1000)
            .toList()
          ..sort();
    double percentile(double fraction) {
      final index = ((values.length - 1) * fraction).ceil();
      return values[index];
    }

    return LatencySummary(
      p50Milliseconds: percentile(0.50),
      p95Milliseconds: percentile(0.95),
      samples: values.length,
    );
  }
}
