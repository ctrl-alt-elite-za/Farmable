/// One walk around a section's edge, and what it measures (#15).
///
/// A [WalkSource] streams [WalkSample]s; a [WalkRecording] keeps them and
/// turns them into a [WalkResult] — the shape to review, the area by AR and
/// by GPS, and whether the two agree. Pure Dart, so every state the walk
/// screen can show is reachable from a unit test with a scripted list of
/// samples.
library;

import 'dart:async';
import 'dart:math' as math;

import 'geometry.dart';

/// Where AR tracking stands at one moment of the walk.
enum ArTracking {
  /// AR is following the phone; the sample's AR position is good.
  tracking,

  /// AR lost the ground — too dark, covered, moved too fast. AR drawing
  /// pauses; GPS keeps recording.
  lost,

  /// This source has no AR at all: a GPS-only walk.
  unavailable,
}

class WalkSample {
  /// Time since the walk started.
  final Duration at;

  /// Ground-plane position in metres. Null unless [tracking] is
  /// [ArTracking.tracking].
  final ArPoint? ar;

  /// The latest location fix, if one came with this sample.
  final GpsPoint? gps;

  final ArTracking tracking;

  const WalkSample({
    required this.at,
    this.ar,
    this.gps,
    this.tracking = ArTracking.unavailable,
  });

  factory WalkSample.fromJson(Map<String, dynamic> j) {
    final ar = j['ar'] as List?;
    final gps = j['gps'] as List?;
    return WalkSample(
      at: Duration(milliseconds: (j['ms'] as num).toInt()),
      ar: ar == null
          ? null
          : ArPoint((ar[0] as num).toDouble(), (ar[1] as num).toDouble()),
      gps: gps == null
          ? null
          : GpsPoint(
              (gps[0] as num).toDouble(),
              (gps[1] as num).toDouble(),
              accuracyMetres: gps.length > 2
                  ? (gps[2] as num).toDouble()
                  : null,
            ),
      tracking: ArTracking.values.byName(j['tracking'] as String),
    );
  }

  Map<String, Object?> toJson() => {
    'ms': at.inMilliseconds,
    if (ar != null) 'ar': [ar!.x, ar!.z],
    if (gps != null)
      'gps': [gps!.latitude, gps!.longitude, ?gps!.accuracyMetres],
    'tracking': tracking.name,
  };
}

/// What a walk's positions come from.
///
/// On a phone today that is GPS alone; AR plane detection needs the native
/// ARKit/ARCore session this app does not have yet. In test mode it is a
/// recorded walk played back — the "fake AR" the widget tests and the Maestro
/// flow use, with AR positions, tracking loss and GPS noise all scripted.
abstract interface class WalkSource {
  /// Whether this source can give AR positions at all.
  bool get hasAr;

  /// Plain words for the walk screen: what is measuring.
  String get description;

  /// Starts measuring. The stream errors with [WalkUnavailable] if it cannot
  /// start — no permission, location off — and closes when [stop] is called
  /// or a recording runs out.
  Stream<WalkSample> start();

  Future<void> stop();
}

/// The walk could not start. [permissionDenied] is the case the farmer can
/// fix in Settings.
class WalkUnavailable implements Exception {
  final String reason;
  final bool permissionDenied;

  const WalkUnavailable(this.reason, {this.permissionDenied = false});

  @override
  String toString() => reason;
}

/// Plays a recorded walk back, sample by sample, at [speed] times real time.
/// A speed of zero sends everything at once, for unit tests.
class ReplayWalkSource implements WalkSource {
  final List<WalkSample> samples;
  final double speed;
  @override
  final String description;

  ReplayWalkSource(
    this.samples, {
    this.speed = 1,
    this.description = 'A recorded walk, played back (test mode)',
  });

  StreamController<WalkSample>? _controller;

  @override
  bool get hasAr => samples.any((s) => s.tracking != ArTracking.unavailable);

  @override
  Stream<WalkSample> start() {
    final controller = StreamController<WalkSample>();
    _controller = controller;
    controller.onListen = () async {
      var previous = Duration.zero;
      // Each playback checks its own controller: a stop followed by a new
      // start must not wake an old loop into adding to a closed stream.
      for (final s in samples) {
        if (controller.isClosed) break;
        if (speed > 0) {
          final wait = (s.at - previous) * (1 / speed);
          previous = s.at;
          if (wait > Duration.zero) await Future<void>.delayed(wait);
        }
        if (controller.isClosed) break;
        controller.add(s);
      }
      if (!controller.isClosed) await controller.close();
    };
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    final c = _controller;
    if (c != null && !c.isClosed) await c.close();
  }
}

/// A walk's measurements, ready to review.
class WalkResult {
  /// The shape to review, open (no repeated closing point), in order.
  final List<GpsPoint> ring;

  /// Area of the AR path, if AR saw enough of the walk.
  final double? arAreaM2;

  /// Area of the GPS path, if GPS saw enough of the walk.
  final double? gpsAreaM2;

  /// How many GPS fixes were dropped for being worse than 20 m.
  final int poorFixesDropped;

  /// True when [ring] came from corners the farmer marked.
  final bool fromMarkedCorners;

  const WalkResult({
    required this.ring,
    required this.arAreaM2,
    required this.gpsAreaM2,
    this.poorFixesDropped = 0,
    this.fromMarkedCorners = false,
  });

  /// AR against GPS, as a fraction — null for a GPS-only walk.
  double? get disagreementFraction => arAreaM2 == null || gpsAreaM2 == null
      ? null
      : disagreement(arAreaM2!, gpsAreaM2!);

  /// The two measurements disagree by more than 15%.
  bool get agreementWarning =>
      (disagreementFraction ?? 0) > agreementWarningFraction;
}

/// The walk so far. Feed it samples; ask it for the live area; [finish] it.
class WalkRecording {
  final List<ArPoint> arPath = [];
  final List<GpsPoint> gpsPath = [];

  /// AR and GPS positions taken at the same moment, for aligning the AR
  /// shape onto the map.
  final List<({ArPoint ar, GpsPoint gps})> anchors = [];

  /// Corners the farmer tapped: the GPS fix, and the AR position if AR was
  /// tracking at the time.
  final List<({ArPoint? ar, GpsPoint gps})> corners = [];

  ArTracking tracking = ArTracking.unavailable;
  GpsPoint? lastFix;
  ArPoint? lastAr;
  int poorFixesDropped = 0;

  /// Metres walked, along the GPS path.
  double get walkedMetres {
    var total = 0.0;
    for (var i = 1; i < gpsPath.length; i++) {
      final step = projectGps(gpsPath[i], gpsPath[i - 1]);
      total += math.sqrt(step.x * step.x + step.z * step.z);
    }
    return total;
  }

  /// How many times AR lost track during the walk.
  int trackingLosses = 0;

  void add(WalkSample s) {
    if (tracking == ArTracking.tracking && s.tracking == ArTracking.lost) {
      trackingLosses++;
    }
    tracking = s.tracking;
    final gps = s.gps;
    if (gps != null) {
      final accuracy = gps.accuracyMetres;
      if (accuracy != null && accuracy > maxGpsAccuracyMetres) {
        poorFixesDropped++;
      } else {
        gpsPath.add(gps);
        lastFix = gps;
      }
    }
    // AR drawing pauses while tracking is lost; GPS carries on above.
    final ar = s.ar;
    if (ar != null && s.tracking == ArTracking.tracking && ar.isFinite) {
      arPath.add(ar);
      lastAr = ar;
      if (gps != null && gps == lastFix) anchors.add((ar: ar, gps: gps));
    }
  }

  /// Marks where the phone is now as a corner. False when there is no fix
  /// yet to mark.
  bool markCorner() {
    final fix = lastFix;
    if (fix == null) return false;
    corners.add((
      ar: tracking == ArTracking.tracking ? lastAr : null,
      gps: fix,
    ));
    return true;
  }

  /// The area walked so far, if the path encloses one yet — AR when it has
  /// it, GPS otherwise. Null rather than a wrong number.
  double? get liveAreaM2 => _tryArea(arPath) ?? _tryGpsArea(gpsPath);

  /// The GPS path as a clean ring: fixes closer together than the GPS can
  /// tell apart are thinned out, then the zig-zag of its noise is simplified
  /// away. Throws [GeometryException] if no shape is left.
  static List<GpsPoint> gpsRing(List<GpsPoint> path) {
    if (path.length < 3) {
      throw const GeometryException(
        GeometryErrorCode.tooFewPoints,
        'Walk further — the path does not go round any land yet.',
      );
    }
    final accuracies = [for (final p in path) ?p.accuracyMetres]..sort();
    // Simplified at about the GPS's own accuracy: finer than that is noise.
    final tolerance = accuracies.isEmpty
        ? 2.0
        : math.max(1.5, accuracies[accuracies.length ~/ 2]);
    final origin = path.first;
    final projected = [for (final g in path) projectGps(g, origin)];
    final thinned = <ArPoint>[projected.first];
    for (final p in projected.skip(1)) {
      final last = thinned.last;
      if (math.sqrt(math.pow(p.x - last.x, 2) + math.pow(p.z - last.z, 2)) >=
          tolerance) {
        thinned.add(p);
      }
    }
    final simple = simplifyRing(thinned, toleranceMetres: tolerance);
    return [
      for (final p in fitRingToPath(
        simple,
        projected,
        cornerClearance: 2 * tolerance,
      ))
        unprojectGps(p, origin),
    ];
  }

  static double? _tryArea(List<ArPoint> path) {
    if (path.length < 3) return null;
    try {
      return planarArea(simplifyRing(path, toleranceMetres: 0.2));
    } on GeometryException {
      return null;
    }
  }

  static double? _tryGpsArea(List<GpsPoint> path) {
    if (path.length < 3) return null;
    try {
      return geodesicArea(gpsRing(path));
    } on GeometryException {
      return null;
    }
  }

  /// The shape to review. Throws [GeometryException] when the walk does not
  /// enclose any land — too short, or a line.
  WalkResult finish() {
    final arArea = _tryArea(arPath);
    final gpsArea = _tryGpsArea(gpsPath);
    final alignment = _alignment();

    List<GpsPoint> ring;
    var fromCorners = false;
    if (corners.length >= 3) {
      fromCorners = true;
      ring = [
        for (final c in corners)
          if (c.ar != null && alignment != null)
            applyAlignment(c.ar!, alignment)
          else
            c.gps,
      ];
    } else if (arArea != null && alignment != null) {
      ring = [
        for (final p in simplifyRing(arPath, toleranceMetres: 0.5))
          applyAlignment(p, alignment),
      ];
    } else {
      ring = gpsRing(gpsPath);
    }
    // Validates the ring: a crossing or a sliver throws here, not on save.
    // Review gets the cleaned corners, so a corner marked twice in one spot
    // is one corner, not a zero-length side that reads as a crossing.
    final closed = closeGpsShape(ring);
    ring = closed.sublist(0, closed.length - 1);
    return WalkResult(
      ring: ring,
      arAreaM2: arArea,
      gpsAreaM2: gpsArea,
      poorFixesDropped: poorFixesDropped,
      fromMarkedCorners: fromCorners,
    );
  }

  Alignment? _alignment() {
    if (anchors.length < 2) return null;
    try {
      return alignArToGps(
        [for (final a in anchors) a.ar],
        [for (final a in anchors) a.gps],
      );
    } on GeometryException {
      return null;
    }
  }
}

/// The review screen's shape as a GeoJSON `Polygon` — `[longitude,
/// latitude]`, closed — which is what `sections.boundary` stores and sync
/// sends.
Map<String, Object?> ringToGeoJson(List<GpsPoint> ring) => {
  'type': 'Polygon',
  'coordinates': [
    [
      for (final p in [...ring, ring.first]) [p.longitude, p.latitude],
    ],
  ],
};

/// Square metres as the API's `area_m2`: a decimal string, two places.
String areaM2String(double m2) => m2.toStringAsFixed(2);

/// Square metres the way a farmer reads them: hectares from a hectare up,
/// square metres below. Spaces are non-breaking, so "1 200 m²" never splits
/// across a line.
String formatArea(double m2) {
  if (m2 >= 10000) return '${(m2 / 10000).toStringAsFixed(2)} ha';
  return '${_grouped(m2.round())} m²';
}

String _grouped(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(' ');
    out.write(s[i]);
  }
  return out.toString();
}
