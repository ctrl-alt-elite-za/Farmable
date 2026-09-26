/// Boundary maths for walking a section (#15), on the phone and offline.
///
/// A Dart port of `packages/geo` — the same rules, the same error codes and
/// the same Earth radius — so a shape the phone accepts is one the TypeScript
/// library and the backend's `geometry.py` accept too. Pure: no Flutter, no
/// plugins, no clock.
///
/// AR positions are metres on the ground plane: x is right/east, z is
/// forward/north, and height is ignored. GPS positions are WGS84 degrees.
/// Every function throws [GeometryException] rather than returning a wrong
/// number.
library;

import 'dart:math' as math;

class ArPoint {
  final double x;
  final double z;

  const ArPoint(this.x, this.z);

  bool get isFinite => x.isFinite && z.isFinite;

  @override
  bool operator ==(Object other) =>
      other is ArPoint && other.x == x && other.z == z;

  @override
  int get hashCode => Object.hash(x, z);

  @override
  String toString() => 'ArPoint($x, $z)';
}

class GpsPoint {
  final double latitude;
  final double longitude;

  /// Radius of 68% confidence, in metres. Null when the source gave none.
  final double? accuracyMetres;

  const GpsPoint(this.latitude, this.longitude, {this.accuracyMetres});

  @override
  bool operator ==(Object other) =>
      other is GpsPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GpsPoint($latitude, $longitude)';
}

enum GeometryErrorCode {
  tooFewPoints,
  invalidCoordinate,
  poorGpsAccuracy,
  selfIntersection,
  degenerateShape,
  invalidOptions,
  invalidAlignment,
}

class GeometryException implements Exception {
  final GeometryErrorCode code;
  final String message;

  const GeometryException(this.code, this.message);

  @override
  String toString() => 'GeometryException(${code.name}): $message';
}

const _epsilon = 1e-8;
const _radians = math.pi / 180;

/// The same mean Earth radius as Turf and `packages/geo`.
const earthRadiusMetres = 6371008.8;

/// A GPS fix worse than this is not used for a boundary.
const maxGpsAccuracyMetres = 20.0;

/// AR and GPS disagreeing by more than this is worth telling the farmer.
const agreementWarningFraction = 0.15;

bool _same(ArPoint a, ArPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.z - b.z, 2)) <= _epsilon;

double _cross(ArPoint a, ArPoint b, ArPoint c) =>
    (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x);

bool _onSegment(ArPoint a, ArPoint b, ArPoint p) =>
    _cross(a, b, p).abs() <= _epsilon &&
    p.x >= math.min(a.x, b.x) - _epsilon &&
    p.x <= math.max(a.x, b.x) + _epsilon &&
    p.z >= math.min(a.z, b.z) - _epsilon &&
    p.z <= math.max(a.z, b.z) + _epsilon;

bool _intersects(ArPoint a, ArPoint b, ArPoint c, ArPoint d) {
  final abC = _cross(a, b, c);
  final abD = _cross(a, b, d);
  final cdA = _cross(c, d, a);
  final cdB = _cross(c, d, b);
  return (((abC > _epsilon && abD < -_epsilon) ||
              (abC < -_epsilon && abD > _epsilon)) &&
          ((cdA > _epsilon && cdB < -_epsilon) ||
              (cdA < -_epsilon && cdB > _epsilon))) ||
      _onSegment(a, b, c) ||
      _onSegment(a, b, d) ||
      _onSegment(c, d, a) ||
      _onSegment(c, d, b);
}

double _signedArea(List<ArPoint> points) {
  // Translated to the first point to avoid cancellation at large offsets.
  final origin = points.first;
  var sum = 0.0;
  for (var i = 1; i < points.length - 1; i++) {
    sum += _cross(origin, points[i], points[i + 1]);
  }
  return sum / 2;
}

void _gpsError(GpsPoint p) {
  if (!p.latitude.isFinite ||
      !p.longitude.isFinite ||
      p.latitude.abs() > 90 ||
      p.longitude.abs() > 180) {
    throw const GeometryException(
      GeometryErrorCode.invalidCoordinate,
      'GPS coordinates must be valid WGS84 degrees.',
    );
  }
  final accuracy = p.accuracyMetres;
  if (accuracy != null) {
    if (!accuracy.isFinite || accuracy < 0) {
      throw const GeometryException(
        GeometryErrorCode.invalidCoordinate,
        'GPS accuracy must be finite and nonnegative.',
      );
    }
    if (accuracy > maxGpsAccuracyMetres) {
      throw const GeometryException(
        GeometryErrorCode.poorGpsAccuracy,
        'GPS accuracy is worse than 20 metres.',
      );
    }
  }
}

/// The indices of [projected] that make a clean open ring: consecutive and
/// closing duplicates dropped, topology checked.
List<int> _ring(List<ArPoint> projected) {
  for (final p in projected) {
    if (!p.isFinite) {
      throw const GeometryException(
        GeometryErrorCode.invalidCoordinate,
        'Coordinates must be finite.',
      );
    }
  }
  final indices = <int>[];
  for (var i = 0; i < projected.length; i++) {
    if (indices.isEmpty || !_same(projected[i], projected[indices.last])) {
      indices.add(i);
    }
  }
  while (indices.length > 1 &&
      _same(projected[indices.first], projected[indices.last])) {
    indices.removeLast();
  }
  if (indices.length < 3) {
    throw const GeometryException(
      GeometryErrorCode.tooFewPoints,
      'A shape needs at least three distinct points.',
    );
  }
  final flat = [for (final i in indices) projected[i]];
  final crossing = firstCrossing(flat);
  if (crossing != null) {
    throw GeometryException(
      GeometryErrorCode.selfIntersection,
      crossing.adjacent
          ? 'Adjacent edges overlap or double back.'
          : 'The shape crosses or touches itself.',
    );
  }
  final area = _signedArea(flat).abs();
  if (!area.isFinite || area <= _epsilon) {
    throw const GeometryException(
      GeometryErrorCode.degenerateShape,
      'The shape must enclose a finite, nonzero area.',
    );
  }
  return indices;
}

/// Where an open ring crosses itself: the two edge indices (edge `i` runs
/// from corner `i` to corner `i + 1`), or null when it is a simple shape.
/// For the review screen, which draws the offending edges.
({int first, int second, bool adjacent})? firstCrossing(List<ArPoint> flat) {
  final n = flat.length;
  for (var i = 0; i < n; i++) {
    final previous = flat[(i + n - 1) % n];
    final current = flat[i];
    final next = flat[(i + 1) % n];
    if (_cross(previous, current, next).abs() <= _epsilon &&
        (current.x - previous.x) * (next.x - current.x) +
                (current.z - previous.z) * (next.z - current.z) <
            -_epsilon) {
      return (first: (i + n - 1) % n, second: i, adjacent: true);
    }
    for (var j = i + 1; j < n; j++) {
      if (j == i + 1 || (i == 0 && j == n - 1)) continue;
      if (_intersects(current, next, flat[j], flat[(j + 1) % n])) {
        return (first: i, second: j, adjacent: false);
      }
    }
  }
  return null;
}

/// Removes consecutive and closing duplicates, validates the shape, and
/// returns it closed (the first point repeated at the end).
List<ArPoint> closeShape(List<ArPoint> points) {
  final clean = [for (final i in _ring(points)) points[i]];
  return [...clean, clean.first];
}

/// Square metres enclosed by an AR walk.
double planarArea(List<ArPoint> points) =>
    _signedArea(closeShape(points)).abs();

double _longitudeDelta(double longitude, double origin) =>
    ((longitude - origin + 540) % 360) - 180;

/// [point] as east/north metres from [origin], on a local flat projection.
/// Good for farm-sized shapes; meaningless across a continent.
ArPoint projectGps(GpsPoint point, GpsPoint origin) => ArPoint(
  _longitudeDelta(point.longitude, origin.longitude) *
      _radians *
      earthRadiusMetres *
      math.cos(origin.latitude * _radians),
  (point.latitude - origin.latitude) * _radians * earthRadiusMetres,
);

/// The inverse of [projectGps].
GpsPoint unprojectGps(ArPoint point, GpsPoint origin) {
  final latitude = origin.latitude + point.z / earthRadiusMetres / _radians;
  final longitude =
      origin.longitude +
      point.x /
          (earthRadiusMetres * math.cos(origin.latitude * _radians)) /
          _radians;
  return GpsPoint(latitude, ((longitude + 180) % 360 + 360) % 360 - 180);
}

List<GpsPoint> closeGpsShape(List<GpsPoint> points) {
  points.forEach(_gpsError);
  if (points.isEmpty) {
    throw const GeometryException(
      GeometryErrorCode.tooFewPoints,
      'A shape needs at least three distinct points.',
    );
  }
  final indices = _ring([for (final p in points) projectGps(p, points.first)]);
  final clean = [for (final i in indices) points[i]];
  return [...clean, clean.first];
}

/// Square metres on the sphere — the same ring formula Turf uses.
double geodesicArea(List<GpsPoint> points) {
  final shape = closeGpsShape(points);
  final origin = shape.first.longitude;
  // Unwrap the dateline so a small field crossing 180° is not globe-sized.
  final coords = [
    for (final p in shape)
      (lon: origin + _longitudeDelta(p.longitude, origin), lat: p.latitude),
  ];
  var total = 0.0;
  final n = coords.length;
  for (var i = 0; i < n; i++) {
    final lower = coords[i];
    final middle = coords[(i + 1) % n];
    final upper = coords[(i + 2) % n];
    total +=
        (upper.lon - lower.lon) * _radians * math.sin(middle.lat * _radians);
  }
  final area = (total * earthRadiusMetres * earthRadiusMetres / 2).abs();
  if (!area.isFinite || area <= _epsilon) {
    throw const GeometryException(
      GeometryErrorCode.degenerateShape,
      'The GPS shape must enclose a finite, nonzero area.',
    );
  }
  return area;
}

class Corner {
  final int index;
  final ArPoint point;
  final double turnDegrees;

  const Corner(this.index, this.point, this.turnDegrees);
}

double _turnDegrees(ArPoint previous, ArPoint current, ArPoint next) {
  final dot =
      (current.x - previous.x) * (next.x - current.x) +
      (current.z - previous.z) * (next.z - current.z);
  return math.atan2(_cross(previous, current, next), dot).abs() / _radians;
}

/// Indices refer to the cleaned, open ring.
List<Corner> detectCorners(List<ArPoint> points, {double minTurnDegrees = 45}) {
  if (!minTurnDegrees.isFinite || minTurnDegrees < 0 || minTurnDegrees > 180) {
    throw const GeometryException(
      GeometryErrorCode.invalidOptions,
      'Corner threshold must be between 0 and 180 degrees.',
    );
  }
  final shape = closeShape(points);
  final open = shape.sublist(0, shape.length - 1);
  final n = open.length;
  return [
    for (var i = 0; i < n; i++)
      if (_turnDegrees(open[(i + n - 1) % n], open[i], open[(i + 1) % n])
          case final angle when angle >= minTurnDegrees)
        Corner(i, open[i], angle),
  ];
}

/// A walked path reduced to the corners that matter: Douglas–Peucker on the
/// closed ring, keeping every point further than [toleranceMetres] from the
/// straight line between its neighbours. What the review map puts a handle
/// on, so a farmer drags four corners, not four hundred footsteps.
///
/// The walked path itself may cross itself — GPS noise zig-zags along every
/// edge — so only the simplified ring is validated. Throws
/// [GeometryException] when that ring is not a usable shape.
List<ArPoint> simplifyRing(List<ArPoint> points, {double toleranceMetres = 1}) {
  for (final p in points) {
    if (!p.isFinite) {
      throw const GeometryException(
        GeometryErrorCode.invalidCoordinate,
        'Coordinates must be finite.',
      );
    }
  }
  final open = <ArPoint>[];
  for (final p in points) {
    if (open.isEmpty || !_same(p, open.last)) open.add(p);
  }
  while (open.length > 1 && _same(open.first, open.last)) {
    open.removeLast();
  }
  if (open.length < 3) {
    throw const GeometryException(
      GeometryErrorCode.tooFewPoints,
      'A shape needs at least three distinct points.',
    );
  }
  if (open.length <= 4) return closeShape(open)..removeLast();

  // Split the ring at the point furthest from the first, so both halves are
  // open polylines with fixed ends.
  var far = 0;
  var farDistance = -1.0;
  for (var i = 1; i < open.length; i++) {
    final d = _distance(open[0], open[i]);
    if (d > farDistance) {
      farDistance = d;
      far = i;
    }
  }
  final a = _douglasPeucker(open.sublist(0, far + 1), toleranceMetres);
  final b = _douglasPeucker([...open.sublist(far), open[0]], toleranceMetres);
  final ring = [...a, ...b.sublist(1, b.length - 1)];
  return closeShape(ring)..removeLast();
}

/// Straightens a simplified [ring] against the noisy [path] it came from.
///
/// Douglas–Peucker keeps real samples as corners, and at a GPS corner the
/// nearest sample is usually a step or two short of it, so the shape comes
/// out cut-cornered and small. Here every sample away from the corners is
/// given to its nearest side, a straight line is fitted through each side's
/// samples, and each corner is put where its two side lines meet. A corner
/// whose sides are too close to parallel to meet reliably is left where it
/// was. Returns [ring] unchanged if the straightened shape is not valid.
List<ArPoint> fitRingToPath(
  List<ArPoint> ring,
  List<ArPoint> path, {
  double cornerClearance = 3,
}) {
  final n = ring.length;
  if (n < 3) return ring;
  final sides = [for (var i = 0; i < n; i++) <ArPoint>[]];
  for (final p in path) {
    if (!p.isFinite) continue;
    if (ring.any((c) => _distance(c, p) < cornerClearance)) continue;
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < n; i++) {
      final d = _distanceToSegmentClamped(p, ring[i], ring[(i + 1) % n]);
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    sides[best].add(p);
  }
  final lines = [for (final side in sides) _fitLine(side)];
  final fitted = <ArPoint>[];
  for (var i = 0; i < n; i++) {
    final before = lines[(i + n - 1) % n];
    final after = lines[i];
    final meet = before == null || after == null ? null : _meet(before, after);
    fitted.add(
      meet != null && _distance(meet, ring[i]) < 4 * cornerClearance
          ? meet
          : ring[i],
    );
  }
  try {
    return closeShape(fitted)..removeLast();
  } on GeometryException {
    return ring;
  }
}

/// A line through [points]: their centre and principal direction.
({ArPoint centre, ArPoint direction})? _fitLine(List<ArPoint> points) {
  if (points.length < 2) return null;
  final c = _centroid(points);
  var sxx = 0.0, szz = 0.0, sxz = 0.0;
  for (final p in points) {
    final dx = p.x - c.x, dz = p.z - c.z;
    sxx += dx * dx;
    szz += dz * dz;
    sxz += dx * dz;
  }
  final angle = 0.5 * math.atan2(2 * sxz, sxx - szz);
  return (centre: c, direction: ArPoint(math.cos(angle), math.sin(angle)));
}

/// Where two lines cross, or null when they are within 20° of parallel.
ArPoint? _meet(
  ({ArPoint centre, ArPoint direction}) a,
  ({ArPoint centre, ArPoint direction}) b,
) {
  final d1 = a.direction, d2 = b.direction;
  final denominator = d1.x * d2.z - d1.z * d2.x;
  if (denominator.abs() < math.sin(20 * _radians)) return null;
  final dx = b.centre.x - a.centre.x, dz = b.centre.z - a.centre.z;
  final t = (dx * d2.z - dz * d2.x) / denominator;
  return ArPoint(a.centre.x + t * d1.x, a.centre.z + t * d1.z);
}

double _distanceToSegmentClamped(ArPoint p, ArPoint a, ArPoint b) {
  final vx = b.x - a.x, vz = b.z - a.z;
  final length2 = vx * vx + vz * vz;
  if (length2 <= _epsilon) return _distance(p, a);
  final t = (((p.x - a.x) * vx + (p.z - a.z) * vz) / length2).clamp(0.0, 1.0);
  return _distance(p, ArPoint(a.x + t * vx, a.z + t * vz));
}

double _distance(ArPoint a, ArPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.z - b.z, 2));

double _distanceToSegment(ArPoint p, ArPoint a, ArPoint b) {
  final length = _distance(a, b);
  if (length <= _epsilon) return _distance(p, a);
  return _cross(a, b, p).abs() / length;
}

List<ArPoint> _douglasPeucker(List<ArPoint> line, double tolerance) {
  if (line.length < 3) return line;
  var index = 0;
  var furthest = 0.0;
  for (var i = 1; i < line.length - 1; i++) {
    final d = _distanceToSegment(line[i], line.first, line.last);
    if (d > furthest) {
      furthest = d;
      index = i;
    }
  }
  if (furthest <= tolerance) return [line.first, line.last];
  final left = _douglasPeucker(line.sublist(0, index + 1), tolerance);
  final right = _douglasPeucker(line.sublist(index), tolerance);
  return [...left.sublist(0, left.length - 1), ...right];
}

class Alignment {
  final GpsPoint origin;

  /// Positive rotation turns AR right toward geographic north.
  final double rotationRadians;

  /// East/north metres relative to [origin], applied after rotation.
  final ArPoint offset;

  /// RMS residual across the paired anchors, in metres. No scale is fitted.
  final double fitErrorMetres;

  const Alignment({
    required this.origin,
    required this.rotationRadians,
    required this.offset,
    required this.fitErrorMetres,
  });
}

ArPoint _rotate(ArPoint p, double angle) {
  final c = math.cos(angle);
  final s = math.sin(angle);
  return ArPoint(p.x * c - p.z * s, p.x * s + p.z * c);
}

ArPoint _centroid(List<ArPoint> points) => ArPoint(
  points.fold(0.0, (sum, p) => sum + p.x) / points.length,
  points.fold(0.0, (sum, p) => sum + p.z) / points.length,
);

/// Least-squares rigid alignment of corresponding anchors, at least two.
Alignment alignArToGps(List<ArPoint> ar, List<GpsPoint> gps) {
  if (ar.length < 2 || ar.length != gps.length) {
    throw const GeometryException(
      GeometryErrorCode.invalidAlignment,
      'Supply at least two corresponding AR/GPS anchors.',
    );
  }
  for (final p in ar) {
    if (!p.isFinite) {
      throw const GeometryException(
        GeometryErrorCode.invalidCoordinate,
        'AR anchors must be finite.',
      );
    }
  }
  gps.forEach(_gpsError);
  final origin = gps.first;
  if (math.cos(origin.latitude * _radians).abs() <= _epsilon) {
    throw const GeometryException(
      GeometryErrorCode.invalidAlignment,
      'A local east/north projection is undefined at the poles.',
    );
  }
  final targets = [for (final p in gps) projectGps(p, origin)];
  final sourceCentre = _centroid(ar);
  final targetCentre = _centroid(targets);
  var dot = 0.0;
  var determinant = 0.0;
  for (var i = 0; i < ar.length; i++) {
    final x = ar[i].x - sourceCentre.x;
    final z = ar[i].z - sourceCentre.z;
    final east = targets[i].x - targetCentre.x;
    final north = targets[i].z - targetCentre.z;
    dot += x * east + z * north;
    determinant += x * north - z * east;
  }
  if (!dot.isFinite ||
      !determinant.isFinite ||
      math.sqrt(dot * dot + determinant * determinant) <= _epsilon) {
    throw const GeometryException(
      GeometryErrorCode.invalidAlignment,
      'Anchors do not determine a finite rotation.',
    );
  }
  final rotation = math.atan2(determinant, dot);
  final centre = _rotate(sourceCentre, rotation);
  final offset = ArPoint(targetCentre.x - centre.x, targetCentre.z - centre.z);
  var squares = 0.0;
  for (var i = 0; i < ar.length; i++) {
    final r = _rotate(ar[i], rotation);
    squares +=
        math.pow(r.x + offset.x - targets[i].x, 2) +
        math.pow(r.z + offset.z - targets[i].z, 2);
  }
  final fit = math.sqrt(squares / ar.length);
  if (!fit.isFinite || !offset.isFinite) {
    throw const GeometryException(
      GeometryErrorCode.invalidAlignment,
      'Alignment exceeded finite coordinate limits.',
    );
  }
  return Alignment(
    origin: origin,
    rotationRadians: rotation,
    offset: offset,
    fitErrorMetres: fit,
  );
}

GpsPoint applyAlignment(ArPoint point, Alignment alignment) {
  if (!point.isFinite) {
    throw const GeometryException(
      GeometryErrorCode.invalidCoordinate,
      'AR coordinates must be finite.',
    );
  }
  final r = _rotate(point, alignment.rotationRadians);
  final result = unprojectGps(
    ArPoint(r.x + alignment.offset.x, r.z + alignment.offset.z),
    alignment.origin,
  );
  _gpsError(result);
  return result;
}

/// How far two measurements of one field disagree, as a fraction of the
/// larger. Symmetric, so it does not matter which is taken as "right".
double disagreement(double a, double b) {
  final larger = math.max(a.abs(), b.abs());
  return larger == 0 ? 0 : (a - b).abs() / larger;
}
