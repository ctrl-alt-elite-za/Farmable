/// The normalized application handoff from the reviewed detector in #16.
/// Raw tensor decoding belongs to the adapter for that exact exported model.
library;

import 'dart:math' as math;
import 'dart:ui';

const cropPromptMapping = {
  'cabbage plant': 'cabbage',
  'cabbage head': 'cabbage',
  'tomato plant': 'tomato',
  'tomato fruit': 'tomato',
  'spinach plant': 'spinach',
};

class CropDetection {
  final String rawLabel;
  final double confidence;
  final Rect box;

  /// Only supplied by a reviewed condition classifier or a labelled replay.
  /// Low crop confidence is not evidence of disease.
  final bool checkSuggested;

  CropDetection({
    required this.rawLabel,
    required this.confidence,
    required this.box,
    this.checkSuggested = false,
  }) {
    if (!cropPromptMapping.containsKey(rawLabel) ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 1 ||
        !box.isFinite ||
        box.isEmpty ||
        box.left < 0 ||
        box.top < 0 ||
        box.right > 1 ||
        box.bottom > 1) {
      throw const FormatException('Invalid normalized crop detection');
    }
  }

  String get crop => cropPromptMapping[rawLabel]!;

  factory CropDetection.fromJson(Map<String, Object?> json) {
    final label = json['raw_label'];
    final confidence = json['confidence'];
    final box = json['box'];
    final warning = json['check_suggested'] ?? false;
    if (label is! String ||
        confidence is! num ||
        box is! Map<String, Object?> ||
        warning is! bool) {
      throw const FormatException('Invalid crop detection handoff');
    }
    double coordinate(String name) {
      final value = box[name];
      if (value is! num) throw const FormatException('Missing box coordinate');
      return value.toDouble();
    }

    return CropDetection(
      rawLabel: label,
      confidence: confidence.toDouble(),
      box: Rect.fromLTRB(
        coordinate('x_min'),
        coordinate('y_min'),
        coordinate('x_max'),
        coordinate('y_max'),
      ),
      checkSuggested: warning,
    );
  }

  CropDetection withBox(Rect value) => CropDetection(
    rawLabel: rawLabel,
    confidence: confidence,
    box: value,
    checkSuggested: checkSuggested,
  );
}

double intersectionOverUnion(Rect a, Rect b) {
  final intersection = a.intersect(b);
  if (intersection.isEmpty) return 0;
  final shared = intersection.width * intersection.height;
  return shared / (a.width * a.height + b.width * b.height - shared);
}

/// Stable, class-aware NMS: one crop cannot suppress a different crop.
List<CropDetection> suppressCropDuplicates(
  Iterable<CropDetection> detections, {
  double minimumConfidence = 0.5,
  double overlapThreshold = 0.5,
}) {
  if (!minimumConfidence.isFinite ||
      minimumConfidence < 0 ||
      minimumConfidence > 1 ||
      !overlapThreshold.isFinite ||
      overlapThreshold <= 0 ||
      overlapThreshold > 1) {
    throw ArgumentError('Invalid detection thresholds');
  }
  final ranked =
      detections.indexed
          .where((entry) => entry.$2.confidence >= minimumConfidence)
          .toList()
        ..sort((a, b) {
          final confidence = b.$2.confidence.compareTo(a.$2.confidence);
          return confidence != 0 ? confidence : a.$1.compareTo(b.$1);
        });
  final kept = <CropDetection>[];
  for (final (_, candidate) in ranked) {
    if (!kept.any(
      (other) =>
          other.crop == candidate.crop &&
          intersectionOverUnion(other.box, candidate.box) >= overlapThreshold,
    )) {
      kept.add(candidate);
    }
  }
  return List.unmodifiable(kept);
}

class TrackedCrop {
  final int id;
  final CropDetection detection;
  final Duration lastSeen;
  const TrackedCrop(this.id, this.detection, this.lastSeen);
}

/// Bounded short-lived tracks, independent of the camera, inference and UI.
class CropTracker {
  final Duration maxAge;
  final double minimumOverlap;
  final double smoothing;
  final _tracks = <TrackedCrop>[];
  var _nextId = 1;
  Duration? _lastUpdate;

  CropTracker({
    this.maxAge = const Duration(milliseconds: 300),
    this.minimumOverlap = 0.2,
    this.smoothing = 0.7,
  }) {
    if (maxAge <= Duration.zero ||
        !minimumOverlap.isFinite ||
        minimumOverlap <= 0 ||
        minimumOverlap > 1 ||
        !smoothing.isFinite ||
        smoothing <= 0 ||
        smoothing > 1) {
      throw ArgumentError('Invalid tracking parameters');
    }
  }

  List<TrackedCrop> update(Iterable<CropDetection> input, Duration timestamp) {
    if (timestamp < Duration.zero ||
        (_lastUpdate != null && timestamp < _lastUpdate!)) {
      throw ArgumentError('Frame timestamps must be monotonic');
    }
    _lastUpdate = timestamp;
    _tracks.removeWhere((track) => timestamp - track.lastSeen >= maxAge);
    final detections = suppressCropDuplicates(input);
    final matches = <({int track, int detection, double overlap})>[];
    for (var t = 0; t < _tracks.length; t++) {
      for (var d = 0; d < detections.length; d++) {
        if (_tracks[t].detection.crop != detections[d].crop) continue;
        final overlap = intersectionOverUnion(
          _tracks[t].detection.box,
          detections[d].box,
        );
        if (overlap >= minimumOverlap) {
          matches.add((track: t, detection: d, overlap: overlap));
        }
      }
    }
    matches.sort((a, b) {
      final overlap = b.overlap.compareTo(a.overlap);
      if (overlap != 0) return overlap;
      final track = a.track.compareTo(b.track);
      return track != 0 ? track : a.detection.compareTo(b.detection);
    });
    final usedTracks = <int>{};
    final usedDetections = <int>{};
    for (final match in matches) {
      if (usedTracks.contains(match.track) ||
          usedDetections.contains(match.detection)) {
        continue;
      }
      usedTracks.add(match.track);
      usedDetections.add(match.detection);
      final old = _tracks[match.track];
      final detection = detections[match.detection];
      _tracks[match.track] = TrackedCrop(
        old.id,
        detection.withBox(
          Rect.lerp(old.detection.box, detection.box, smoothing)!,
        ),
        timestamp,
      );
    }
    for (var d = 0; d < detections.length; d++) {
      if (!usedDetections.contains(d)) {
        _tracks.add(TrackedCrop(_nextId++, detections[d], timestamp));
      }
    }
    return List.unmodifiable(_tracks);
  }

  void reset() {
    _tracks.clear();
    _lastUpdate = null;
    // IDs are not reused, so a stale tap cannot select a new plant.
  }
}

/// Maps upright normalized boxes through a centred BoxFit.cover preview.
Rect cropPreviewBox(Rect normalized, Size image, Size viewport) {
  if (!image.width.isFinite ||
      !image.height.isFinite ||
      image.isEmpty ||
      !viewport.width.isFinite ||
      !viewport.height.isFinite ||
      viewport.isEmpty) {
    throw ArgumentError('Preview dimensions must be positive and finite');
  }
  final scale = math.max(
    viewport.width / image.width,
    viewport.height / image.height,
  );
  final width = image.width * scale;
  final height = image.height * scale;
  return Rect.fromLTRB(
    normalized.left * width + (viewport.width - width) / 2,
    normalized.top * height + (viewport.height - height) / 2,
    normalized.right * width + (viewport.width - width) / 2,
    normalized.bottom * height + (viewport.height - height) / 2,
  );
}
