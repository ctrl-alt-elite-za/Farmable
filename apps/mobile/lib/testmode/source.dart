import 'dart:convert';

import 'package:flutter/services.dart';

import '../app/config.dart';

const simulatedFixture = 'assets/testmode/sample-detections.json';

class SimulatedDetection {
  final String label;
  final double confidence;
  final List<double> box;

  const SimulatedDetection({
    required this.label,
    required this.confidence,
    required this.box,
  });

  factory SimulatedDetection.fromJson(Map<String, dynamic> json) =>
      SimulatedDetection(
        label: json['label'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        box: (json['box'] as List)
            .map((value) => (value as num).toDouble())
            .toList(),
      );
}

class SimulatedFrame {
  final int index;
  final int timestampMs;
  final List<SimulatedDetection> detections;

  const SimulatedFrame({
    required this.index,
    required this.timestampMs,
    required this.detections,
  });

  factory SimulatedFrame.fromJson(Map<String, dynamic> json) => SimulatedFrame(
        index: json['index'] as int,
        timestampMs: json['timestamp_ms'] as int,
        detections: (json['detections'] as List)
            .map((detection) =>
                SimulatedDetection.fromJson(detection as Map<String, dynamic>))
            .toList(),
      );
}

class SimulatedFrameSource {
  const SimulatedFrameSource();

  Future<List<SimulatedFrame>> load() async {
    if (!testMode) {
      throw StateError('Simulated frames are available only in TEST_MODE');
    }
    return loadFixture();
  }

  /// Loads the bundled recording without consulting the compile-time mode.
  /// Production callers should use [load], which remains mode-gated.
  Future<List<SimulatedFrame>> loadFixture() async {
    final decoded = jsonDecode(await rootBundle.loadString(simulatedFixture));
    final frames = (decoded as Map<String, dynamic>)['frames'] as List;
    return frames
        .map((frame) => SimulatedFrame.fromJson(frame as Map<String, dynamic>))
        .toList(growable: false);
  }
}
