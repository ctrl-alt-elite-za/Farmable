import 'dart:math' as math;

import 'scan_models.dart';

double intersectionOverUnion(NormalizedBox a, NormalizedBox b) {
  final left = math.max(a.x, b.x);
  final top = math.max(a.y, b.y);
  final right = math.min(a.x + a.width, b.x + b.width);
  final bottom = math.min(a.y + a.height, b.y + b.height);
  final intersection =
      math.max(0.0, right - left) * math.max(0.0, bottom - top);
  final union = a.width * a.height + b.width * b.height - intersection;
  return union <= 0 ? 0 : intersection / union;
}

List<Detection> nonMaxSuppression(
  Iterable<Detection> detections, {
  double overlapThreshold = 0.45,
}) {
  final remaining = detections.toList()
    ..sort((a, b) => b.confidence.compareTo(a.confidence));
  final result = <Detection>[];
  while (remaining.isNotEmpty) {
    final candidate = remaining.removeAt(0);
    result.add(candidate);
    remaining.removeWhere(
      (other) =>
          other.label == candidate.label &&
          intersectionOverUnion(candidate.box, other.box) >= overlapThreshold,
    );
  }
  return result;
}

class CropTracker {
  final double matchIou;
  final int maxMissedFrames;
  List<CropTrack> _tracks = [];
  int _nextId = 1;

  CropTracker({this.matchIou = 0.15, this.maxMissedFrames = 4});

  List<CropTrack> update(Iterable<Detection> rawDetections) {
    final detections = nonMaxSuppression(rawDetections);
    final used = <int>{};
    final updated = <CropTrack>[];

    for (final track in _tracks) {
      var bestIndex = -1;
      var bestIou = matchIou;
      for (var index = 0; index < detections.length; index += 1) {
        if (used.contains(index)) continue;
        final iou = intersectionOverUnion(track.box, detections[index].box);
        if (iou > bestIou) {
          bestIou = iou;
          bestIndex = index;
        }
      }
      if (bestIndex < 0) {
        updated.add(track.missed());
      } else {
        used.add(bestIndex);
        final detection = detections[bestIndex];
        updated.add(
          CropTrack(
            id: track.id,
            label: detection.label,
            confidence: detection.confidence,
            box: detection.box,
          ),
        );
      }
    }

    for (var index = 0; index < detections.length; index += 1) {
      if (used.contains(index)) continue;
      final detection = detections[index];
      updated.add(
        CropTrack(
          id: _nextId++,
          label: detection.label,
          confidence: detection.confidence,
          box: detection.box,
        ),
      );
    }
    _tracks = updated
        .where((track) => track.missedFrames <= maxMissedFrames)
        .toList();
    return _tracks.where((track) => track.missedFrames == 0).toList();
  }

  void reset() {
    _tracks = [];
    _nextId = 1;
  }
}
