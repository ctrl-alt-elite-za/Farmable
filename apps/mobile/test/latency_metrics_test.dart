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
}
