/// Walks played back in test mode, in place of a phone walking a field.
///
/// Built from a fixed recipe rather than stored as files, so the numbers
/// they must produce can be read straight off the recipe: a 40 m by 30 m
/// field is 1 200 m². The noise is deterministic, so every run — widget
/// test, Maestro flow, demo on an emulator — draws the same shape.
///
/// Chosen with `--dart-define=WALK_REPLAY=<name>` on a `TEST_MODE` build.
library;

import 'dart:math' as math;

import '../../domain/mapping/geometry.dart';
import '../../domain/mapping/walk.dart';

/// Where the recorded field lies: a smallholding outside Pretoria.
const recordedFieldOrigin = GpsPoint(-25.7479, 28.2293);

/// The field's true size, which review must show to within 1%.
const recordedFieldAreaM2 = 1200.0;

const _east = 40.0;
const _north = 30.0;

/// Which recorded walk to play.
enum RecordedWalk {
  /// AR and GPS, with AR losing track for a stretch of the second side. The
  /// two agree.
  field,

  /// The same walk, but the GPS drifts — each side comes out 15% long, the
  /// area about a third too big — so AR and GPS disagree by more than 15%.
  drift,

  /// No AR at all: what a phone without ARCore records.
  gpsOnly;

  static RecordedWalk parse(String name) => switch (name) {
    'drift' => drift,
    'gps-only' || 'gpsOnly' => gpsOnly,
    _ => field,
  };
}

/// The walk as samples, half a second apart, at an easy 1.2 m/s.
List<WalkSample> recordedWalk(RecordedWalk which) {
  const step = 0.6; // metres per sample
  const perimeter = 2 * (_east + _north);
  final count = (perimeter / step).round();
  // The AR session's "forward" is wherever the phone faced when it started:
  // here 20° off north, so the AR shape has to be turned to sit on the map.
  const arHeading = 20 * math.pi / 180;
  final random = math.Random(15);
  double jitter(double size) => (random.nextDouble() * 2 - 1) * size;
  // GPS error wanders slowly rather than jumping every step, as a real
  // receiver's does: a smoothed random walk, a metre or two either way.
  var driftX = 0.0, driftZ = 0.0;

  return [
    for (var i = 0; i <= count; i++)
      () {
        final ground = _alongEdge(i * step % perimeter);
        final lost = which != RecordedWalk.gpsOnly && i >= 70 && i < 90;
        final tracking = which == RecordedWalk.gpsOnly
            ? ArTracking.unavailable
            : lost
            ? ArTracking.lost
            : ArTracking.tracking;
        final gpsGround = which == RecordedWalk.drift
            ? ArPoint(ground.x * 1.15, ground.z * 1.15)
            : ground;
        driftX = 0.92 * driftX + jitter(0.5);
        driftZ = 0.92 * driftZ + jitter(0.5);
        final gps = unprojectGps(
          ArPoint(
            gpsGround.x + driftX + jitter(0.2),
            gpsGround.z + driftZ + jitter(0.2),
          ),
          recordedFieldOrigin,
        );
        // Undo the heading: world east/north into the AR session's frame.
        final c = math.cos(-arHeading);
        final s = math.sin(-arHeading);
        final ar = ArPoint(
          ground.x * c - ground.z * s + jitter(0.05),
          ground.x * s + ground.z * c + jitter(0.05),
        );
        return WalkSample(
          at: Duration(milliseconds: i * 500),
          ar: tracking == ArTracking.tracking ? ar : null,
          gps: GpsPoint(
            gps.latitude,
            gps.longitude,
            accuracyMetres: 3 + jitter(1).abs(),
          ),
          tracking: tracking,
        );
      }(),
  ];
}

/// East/north metres at [d] metres along the field's edge, anticlockwise
/// from the south-west corner.
ArPoint _alongEdge(double d) {
  if (d < _east) return ArPoint(d, 0);
  d -= _east;
  if (d < _north) return ArPoint(_east, d);
  d -= _north;
  if (d < _east) return ArPoint(_east - d, _north);
  d -= _east;
  return ArPoint(0, _north - d);
}
