// The same synthetic walks as packages/geo/tests/fixtures/synthetic-walks.ts,
// so the Dart port is held to the TypeScript library's answers.
import 'dart:math' as math;

import 'package:almanac/domain/mapping/geometry.dart';
import 'package:flutter_test/flutter_test.dart';

const square20m = [
  ArPoint(0, 0),
  ArPoint(20, 0),
  ArPoint(20, 20),
  ArPoint(0, 20),
];

const figureEight = [
  ArPoint(0, 0),
  ArPoint(20, 20),
  ArPoint(0, 20),
  ArPoint(20, 0),
];

const shakyWalk = [
  ArPoint(0, 0),
  ArPoint(5, 0.08),
  ArPoint(10, -0.08),
  ArPoint(15, 0.08),
  ArPoint(20, 0),
  ArPoint(20, 20),
  ArPoint(0, 20),
];

const gpsSquare = [
  GpsPoint(-26.02, 28.05, accuracyMetres: 3),
  GpsPoint(-26.02, 28.0502, accuracyMetres: 3),
  GpsPoint(-26.01982, 28.0502, accuracyMetres: 3),
  GpsPoint(-26.01982, 28.05, accuracyMetres: 3),
];

Matcher throwsGeometry(GeometryErrorCode code) =>
    throwsA(isA<GeometryException>().having((e) => e.code, 'code', code));

void main() {
  group('shape and area', () {
    test('a 20 m square is 400 m², either way round', () {
      expect(planarArea(square20m), closeTo(400, 1e-8));
      expect(planarArea(square20m.reversed.toList()), closeTo(400, 1e-8));
    });

    test('fewer than three distinct points is not a shape', () {
      for (final points in [
        <ArPoint>[],
        [square20m[0]],
        square20m.sublist(0, 2),
        List.filled(5, square20m[0]),
        [square20m[0], square20m[1], square20m[1], square20m[0]],
      ]) {
        expect(
          () => planarArea(points),
          throwsGeometry(GeometryErrorCode.tooFewPoints),
        );
      }
    });

    test('a figure of eight is refused', () {
      expect(
        () => closeShape(figureEight),
        throwsGeometry(GeometryErrorCode.selfIntersection),
      );
      expect(
        () => planarArea(figureEight.reversed.toList()),
        throwsGeometry(GeometryErrorCode.selfIntersection),
      );
      expect(firstCrossing(figureEight), isNotNull);
      expect(firstCrossing(square20m), isNull);
    });

    test('duplicates are dropped and the ring is closed', () {
      final points = [
        for (final p in square20m) ...[p, p],
        square20m[0],
        square20m[0],
      ];
      final closed = closeShape(points);
      expect(closed, [...square20m, square20m[0]]);
      expect(closeShape(closed), closed);
      expect(points, hasLength(10));
    });

    test('non-finite coordinates are refused', () {
      for (final bad in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => planarArea([ArPoint(bad, 0), ...square20m]),
          throwsGeometry(GeometryErrorCode.invalidCoordinate),
        );
      }
    });

    test('stays exact far from the origin', () {
      final moved = [for (final p in square20m) ArPoint(p.x + 1e9, p.z - 1e9)];
      expect(planarArea(moved), 400);
    });

    test('touching and doubling-back edges are refused', () {
      expect(
        () => closeShape(const [
          ArPoint(0, 0),
          ArPoint(10, 0),
          ArPoint(10, 10),
          ArPoint(5, 0),
          ArPoint(0, 10),
        ]),
        throwsGeometry(GeometryErrorCode.selfIntersection),
      );
      expect(
        () => closeShape(const [
          ArPoint(0, 0),
          ArPoint(10, 0),
          ArPoint(5, 0),
          ArPoint(5, 10),
        ]),
        throwsGeometry(GeometryErrorCode.selfIntersection),
      );
    });

    test('concave shapes and straight-line samples are fine', () {
      expect(
        planarArea(const [
          ArPoint(0, 0),
          ArPoint(5, 0),
          ArPoint(10, 0),
          ArPoint(10, 10),
          ArPoint(5, 5),
          ArPoint(0, 10),
        ]),
        75,
      );
    });

    test('a vanishing shape is refused rather than measured', () {
      expect(
        () => planarArea(const [
          ArPoint(0, 0),
          ArPoint(1e-4, 0),
          ArPoint(0.5e-4, 0.5e-4),
        ]),
        throwsGeometry(GeometryErrorCode.degenerateShape),
      );
    });
  });

  group('GPS', () {
    test('the WGS84 fixture is close to 400 m²', () {
      final area = geodesicArea(gpsSquare);
      expect(area, greaterThan(398));
      expect(area, lessThan(402));
    });

    test('a fix worse than 20 m is refused', () {
      expect(
        () => geodesicArea([
          ...gpsSquare.sublist(0, 3),
          const GpsPoint(-26.01982, 28.05, accuracyMetres: 25),
        ]),
        throwsGeometry(GeometryErrorCode.poorGpsAccuracy),
      );
    });

    test('out-of-range degrees are refused', () {
      expect(
        () => geodesicArea([const GpsPoint(91, 0), ...gpsSquare]),
        throwsGeometry(GeometryErrorCode.invalidCoordinate),
      );
    });

    test('projection round-trips', () {
      final origin = gpsSquare.first;
      for (final p in gpsSquare) {
        final back = unprojectGps(projectGps(p, origin), origin);
        expect(back.latitude, closeTo(p.latitude, 1e-9));
        expect(back.longitude, closeTo(p.longitude, 1e-9));
      }
    });

    test('agrees with the flat projection at farm scale', () {
      final flat = planarArea([
        for (final p in gpsSquare) projectGps(p, gpsSquare.first),
      ]);
      expect(disagreement(flat, geodesicArea(gpsSquare)), lessThan(0.001));
    });
  });

  group('corners and simplification', () {
    test('a square has four right-angle corners', () {
      final corners = detectCorners(square20m);
      expect(corners, hasLength(4));
      for (final c in corners) {
        expect(c.turnDegrees, closeTo(90, 1e-9));
      }
    });

    test('a shaky side keeps its area close', () {
      expect(planarArea(shakyWalk), closeTo(400, 1));
      expect(detectCorners(shakyWalk).length, greaterThanOrEqualTo(4));
    });

    test('a densely sampled walk simplifies to its corners', () {
      final walk = <ArPoint>[
        for (var i = 0; i < 20; i++) ArPoint(i.toDouble(), 0.05 * (i % 2)),
        for (var i = 0; i < 20; i++) ArPoint(20, i.toDouble()),
        for (var i = 20; i > 0; i--) ArPoint(i.toDouble(), 20),
        for (var i = 20; i > 0; i--) ArPoint(0, i.toDouble()),
      ];
      final ring = simplifyRing(walk);
      expect(ring, hasLength(4));
      expect(disagreement(planarArea(ring), planarArea(walk)), lessThan(0.01));
    });

    test('a corner-less option is refused', () {
      expect(
        () => detectCorners(square20m, minTurnDegrees: 200),
        throwsGeometry(GeometryErrorCode.invalidOptions),
      );
    });
  });

  group('alignment', () {
    test('recovers a known rotation and offset', () {
      const origin = GpsPoint(-26.02, 28.05);
      const angle = math.pi / 6;
      final gps = [
        for (final p in square20m)
          unprojectGps(
            ArPoint(
              p.x * math.cos(angle) - p.z * math.sin(angle) + 3,
              p.x * math.sin(angle) + p.z * math.cos(angle) - 2,
            ),
            origin,
          ),
      ];
      final alignment = alignArToGps(square20m, gps);
      expect(alignment.rotationRadians, closeTo(angle, 1e-6));
      expect(alignment.fitErrorMetres, lessThan(1e-3));
      for (var i = 0; i < square20m.length; i++) {
        final back = applyAlignment(square20m[i], alignment);
        expect(back.latitude, closeTo(gps[i].latitude, 1e-9));
        expect(back.longitude, closeTo(gps[i].longitude, 1e-9));
      }
    });

    test('needs two paired anchors', () {
      expect(
        () => alignArToGps(square20m.sublist(0, 1), gpsSquare.sublist(0, 1)),
        throwsGeometry(GeometryErrorCode.invalidAlignment),
      );
      expect(
        () => alignArToGps(square20m, gpsSquare.sublist(0, 3)),
        throwsGeometry(GeometryErrorCode.invalidAlignment),
      );
    });
  });

  group('agreement', () {
    test('is symmetric and a fraction of the larger', () {
      expect(disagreement(100, 85), closeTo(0.15, 1e-12));
      expect(disagreement(85, 100), closeTo(0.15, 1e-12));
      expect(disagreement(0, 0), 0);
    });

    test('warns only above 15%', () {
      expect(disagreement(100, 85) > agreementWarningFraction, isFalse);
      expect(disagreement(100, 84) > agreementWarningFraction, isTrue);
    });
  });
}
