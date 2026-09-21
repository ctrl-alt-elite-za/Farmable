import 'package:almanac/features/scan/latency_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports deterministic p50 and p95 camera-to-visible latency', () {
    final metrics = ScanLatencyMetrics();
    for (var milliseconds = 1; milliseconds <= 20; milliseconds += 1) {
      metrics.recordCameraToVisible(Duration(milliseconds: milliseconds));
    }

    final summary = metrics.summary!;
    expect(summary.samples, 20);
    expect(summary.p50Milliseconds, 11);
    expect(summary.p95Milliseconds, 20);
  });

  test('requires complete chronological pipeline timestamps', () {
    final metrics = ScanLatencyMetrics();
    final captured = DateTime(2026, 1, 1);
    expect(
      () => metrics.recordFrame(
        capturedAt: captured,
        inferenceStartedAt: captured.subtract(const Duration(milliseconds: 1)),
        inferenceEndedAt: captured,
        overlayRenderedAt: captured,
      ),
      throwsArgumentError,
    );
  });

  test('bounds retained latency samples for long-running scans', () {
    final metrics = ScanLatencyMetrics(maxSamples: 3);
    metrics
      ..recordCameraToVisible(const Duration(milliseconds: 1))
      ..recordCameraToVisible(const Duration(milliseconds: 2))
      ..recordCameraToVisible(const Duration(milliseconds: 3))
      ..recordCameraToVisible(const Duration(milliseconds: 4));

    final summary = metrics.summary!;
    expect(summary.samples, 3);
    expect(summary.p50Milliseconds, 3);
    expect(summary.p95Milliseconds, 4);
  });

  test('rejects an empty sample capacity', () {
    expect(() => ScanLatencyMetrics(maxSamples: 0), throwsArgumentError);
  });
}
