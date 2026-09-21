import { describe, expect, it } from 'vitest';
import {
  alignArToGps,
  applyAlignment,
  closeGpsShape,
  closeShape,
  detectCorners,
  geodesicArea,
  planarArea,
  smoothShape,
  type Alignment,
  type ArPoint,
  type GeometryErrorCode,
  type GpsPoint,
  type Result,
} from '../src/index';
import { figureEight, gpsSquare, shakyWalk, square20m } from './fixtures/synthetic-walks';

function value<T>(result: Result<T>): T {
  expect(result.ok).toBe(true);
  if (!result.ok) throw new Error(result.error.message);
  return result.value;
}

function error<T>(result: Result<T>, code: GeometryErrorCode): void {
  expect(result.ok).toBe(false);
  if (!result.ok) expect(result.error.code).toBe(code);
}

describe('shape and area', () => {
  it('area_square_20m', () => {
    expect(value(planarArea(square20m))).toBeCloseTo(400, 8);
    expect(value(planarArea([...square20m].reverse()))).toBeCloseTo(400, 8);
  });

  it('too_few_points_error', () => {
    for (const points of [[], [square20m[0]], square20m.slice(0, 2)]) {
      error(planarArea(points), 'TOO_FEW_POINTS');
    }
  });

  it('rejects_figure_eight', () => {
    error(closeShape(figureEight), 'SELF_INTERSECTION');
    error(planarArea([...figureEight].reverse()), 'SELF_INTERSECTION');
    error(smoothShape(figureEight), 'SELF_INTERSECTION');
    error(detectCorners(figureEight), 'SELF_INTERSECTION');
  });

  it('removes consecutive and closing duplicates without mutating input', () => {
    const points = Object.freeze([
      ...square20m.flatMap((point) => [Object.freeze({ ...point }), Object.freeze({ ...point })]),
      square20m[0],
      square20m[0],
    ]);
    const closed = value(closeShape(points));
    expect(closed).toEqual([...square20m, square20m[0]]);
    expect(value(closeShape(closed))).toEqual(closed);
    expect(points).toHaveLength(10);
  });

  it('rejects identical points and a two-point walk hidden by duplicates', () => {
    error(closeShape(Array(5).fill(square20m[0])), 'TOO_FEW_POINTS');
    error(closeShape([square20m[0], square20m[1], square20m[1], square20m[0]]), 'TOO_FEW_POINTS');
  });

  it.each([NaN, Infinity, -Infinity])('rejects nonfinite coordinates %s', (bad) => {
    error(planarArea([{ x: bad, z: 0 }, ...square20m]), 'INVALID_COORDINATE');
    error(planarArea([{ x: 0, z: bad }, ...square20m]), 'INVALID_COORDINATE');
  });

  it('ignores height and remains accurate with large coordinate offsets', () => {
    const translated = square20m.map((point) => ({ x: point.x + 1e9, z: point.z - 1e9, y: NaN }));
    expect(value(planarArea(translated))).toBe(400);
  });

  it('rejects repeated nonconsecutive vertices and touching edges', () => {
    error(closeShape([...square20m, square20m[1], { x: -5, z: 10 }]), 'SELF_INTERSECTION');
    error(
      closeShape([
        { x: 0, z: 0 },
        { x: 10, z: 0 },
        { x: 10, z: 10 },
        { x: 5, z: 0 },
        { x: 0, z: 10 },
      ]),
      'SELF_INTERSECTION',
    );
  });

  it('rejects overlapping adjacent edges, including across the closing edge', () => {
    error(
      closeShape([
        { x: 0, z: 0 },
        { x: 10, z: 0 },
        { x: 5, z: 0 },
        { x: 5, z: 10 },
      ]),
      'SELF_INTERSECTION',
    );
    error(
      closeShape([
        { x: 0, z: 0 },
        { x: 5, z: 0 },
        { x: 5, z: 10 },
        { x: 10, z: 0 },
      ]),
      'SELF_INTERSECTION',
    );
  });

  it('accepts concave rings and redundant straight-line samples', () => {
    expect(
      value(
        planarArea([
          { x: 0, z: 0 },
          { x: 5, z: 0 },
          { x: 10, z: 0 },
          { x: 10, z: 10 },
          { x: 5, z: 5 },
          { x: 0, z: 10 },
        ]),
      ),
    ).toBe(75);
  });

  it('rejects zero and overflowed area rather than returning an incorrect number', () => {
    error(
      planarArea([
        { x: 0, z: 0 },
        { x: 1e-4, z: 0 },
        { x: 0.5e-4, z: 0.5e-4 },
      ]),
      'DEGENERATE_SHAPE',
    );
    error(
      planarArea([
        { x: -1e200, z: -1e200 },
        { x: 1e200, z: -1e200 },
        { x: 1e200, z: 1e200 },
        { x: -1e200, z: 1e200 },
      ]),
      'DEGENERATE_SHAPE',
    );
  });
});

describe('GPS', () => {
  it('calculates the fixed WGS84 fixture near 400 square metres', () => {
    expect(value(geodesicArea(gpsSquare))).toBeGreaterThan(398);
    expect(value(geodesicArea(gpsSquare))).toBeLessThan(402);
    expect(value(geodesicArea([...gpsSquare].reverse()))).toBeCloseTo(
      value(geodesicArea(gpsSquare)),
      4,
    );
  });

  it('closes GPS rings and removes duplicate samples', () => {
    const closed = value(closeGpsShape([gpsSquare[0], ...gpsSquare, gpsSquare[0]]));
    expect(closed).toEqual([...gpsSquare, gpsSquare[0]]);
    expect(value(geodesicArea(closed))).toBeCloseTo(value(geodesicArea(gpsSquare)), 8);
  });

  it.each([
    { latitude: NaN, longitude: 0 },
    { latitude: 0, longitude: Infinity },
    { latitude: 91, longitude: 0 },
    { latitude: -91, longitude: 0 },
    { latitude: 0, longitude: 181 },
    { latitude: 0, longitude: -181 },
    { latitude: 0, longitude: 0, accuracyMetres: -1 },
    { latitude: 0, longitude: 0, accuracyMetres: NaN },
    { latitude: 0, longitude: 0, accuracyMetres: Infinity },
  ])('rejects invalid GPS input %j', (point) => {
    error(geodesicArea([point, ...gpsSquare]), 'INVALID_COORDINATE');
  });

  it('rejects accuracy above 20 m, including discarded duplicate samples', () => {
    error(
      geodesicArea([...gpsSquare, { ...gpsSquare[0], accuracyMetres: 20.001 }]),
      'POOR_GPS_ACCURACY',
    );
    expect(
      value(geodesicArea(gpsSquare.map((point) => ({ ...point, accuracyMetres: 20 })))),
    ).toBeGreaterThan(0);
  });

  it('returns typed errors for empty, identical and crossing GPS walks', () => {
    error(geodesicArea([]), 'TOO_FEW_POINTS');
    error(closeGpsShape(Array(3).fill(gpsSquare[0])), 'TOO_FEW_POINTS');
    error(
      geodesicArea([gpsSquare[0], gpsSquare[2], gpsSquare[3], gpsSquare[1]]),
      'SELF_INTERSECTION',
    );
  });

  it('unwraps a small field crossing the antimeridian', () => {
    const dateline = gpsSquare.map((point) => ({
      ...point,
      longitude: point.longitude === 28.05 ? 179.9999 : -179.9999,
    }));
    expect(value(geodesicArea(dateline))).toBeCloseTo(value(geodesicArea(gpsSquare)), 2);
  });
});

describe('smoothing and corners', () => {
  it('detects the four square corners, not its collinear intermediate sample', () => {
    const corners = value(detectCorners([square20m[0], { x: 10, z: 0 }, ...square20m.slice(1)]));
    expect(corners.map((corner) => corner.index)).toEqual([0, 2, 3, 4]);
    expect(corners.every((corner) => Math.abs(corner.turnDegrees - 90) < 1e-6)).toBe(true);
    expect(value(detectCorners(square20m, 100))).toEqual([]);
  });

  it.each([-1, 181, NaN, Infinity])('rejects invalid corner threshold %s', (threshold) => {
    error(detectCorners(square20m, threshold), 'INVALID_OPTIONS');
  });

  it('smooths walking noise while preserving sharp corners and a valid closed shape', () => {
    const smoothed = value(smoothShape(shakyWalk, { iterations: 2 }));
    expect(smoothed[0]).toEqual(shakyWalk[0]);
    expect(smoothed[4]).toEqual(shakyWalk[4]);
    expect(Math.abs(smoothed[2].z)).toBeLessThan(Math.abs(shakyWalk[2].z));
    expect(smoothed.at(-1)).toEqual(smoothed[0]);
    expect(value(planarArea(smoothed))).toBeCloseTo(400, 0);
    expect(shakyWalk[2].z).toBe(-0.08);
  });

  it('supports zero iterations/strength and preserves square corners by default', () => {
    const closed = value(closeShape(square20m));
    expect(value(smoothShape(square20m))).toEqual(closed);
    expect(value(smoothShape(square20m, { iterations: 0 }))).toEqual(closed);
    expect(value(smoothShape(shakyWalk, { strength: 0 }))).toEqual(value(closeShape(shakyWalk)));
  });

  it.each([
    { strength: -0.01 },
    { strength: 1.01 },
    { strength: NaN },
    { iterations: -1 },
    { iterations: 1.5 },
    { iterations: 101 },
    { iterations: Infinity },
    { cornerThresholdDegrees: -1 },
    { cornerThresholdDegrees: 181 },
    { cornerThresholdDegrees: NaN },
  ])('rejects invalid smoothing options %j', (options) => {
    error(smoothShape(square20m, options), 'INVALID_OPTIONS');
  });

  it('revalidates smoothing output instead of silently returning a collapsed shape', () => {
    const result = smoothShape(square20m, {
      strength: 1,
      iterations: 2,
      cornerThresholdDegrees: 180,
    });
    error(result, 'TOO_FEW_POINTS');
  });
});

const origin: GpsPoint = { latitude: -26, longitude: 28, accuracyMetres: 2 };
const anchors: readonly ArPoint[] = [
  { x: 5, z: 10 },
  { x: 25, z: 10 },
  { x: 25, z: 30 },
  { x: 5, z: 30 },
];
// Independent forward fixture conversion, for small local walks.
function gpsAt(east: number, north: number, reference = origin): GpsPoint {
  return {
    latitude: reference.latitude + ((north / 6371008.8) * 180) / Math.PI,
    longitude:
      reference.longitude +
      ((east / (6371008.8 * Math.cos((reference.latitude * Math.PI) / 180))) * 180) / Math.PI,
    accuracyMetres: 2,
  };
}
const rotatedGps = anchors.map((point) =>
  gpsAt(
    point.x * Math.cos(Math.PI / 6) - point.z * Math.sin(Math.PI / 6) + 100,
    point.x * Math.sin(Math.PI / 6) + point.z * Math.cos(Math.PI / 6) + 200,
  ),
);

describe('alignment', () => {
  it('align_rotated_30deg', () => {
    const alignment = value(alignArToGps(anchors, rotatedGps));
    expect(alignment.rotationRadians).toBeCloseTo(Math.PI / 6, 4);
    expect(alignment.fitErrorMetres).toBeLessThan(1);
    for (let i = 0; i < anchors.length; i++) {
      const gps = value(applyAlignment(anchors[i], alignment));
      expect(gps.latitude).toBeCloseTo(rotatedGps[i].latitude, 7);
      expect(gps.longitude).toBeCloseTo(rotatedGps[i].longitude, 7);
    }
  });

  it('fits translation from two distinct pairs with no scale fitting', () => {
    const ar = [
      { x: 10, z: 20 },
      { x: 30, z: 20 },
    ];
    const gps = [gpsAt(0, 0), gpsAt(20, 0)];
    const alignment = value(alignArToGps(ar, gps));
    expect(alignment.rotationRadians).toBeCloseTo(0, 8);
    expect(alignment.offset.x).toBeCloseTo(-10, 5);
    expect(alignment.offset.z).toBeCloseTo(-20, 5);
    expect(alignment.fitErrorMetres).toBeLessThan(0.001);
    const scaled = value(alignArToGps(ar, [gpsAt(0, 0), gpsAt(40, 0)]));
    expect(scaled.fitErrorMetres).toBeCloseTo(10, 4);
  });

  it('reports nonzero residuals from noisy paired anchors', () => {
    const noisy = rotatedGps.map((point, index) => ({
      ...point,
      latitude: point.latitude + (index === 2 ? 0.00001 : 0),
    }));
    const alignment = value(alignArToGps(anchors, noisy));
    expect(alignment.fitErrorMetres).toBeGreaterThan(0.1);
    expect(alignment.fitErrorMetres).toBeLessThan(1);
  });

  it('aligns anchors across the dateline and wraps transformed longitude', () => {
    const reference = { latitude: 0, longitude: 179.9999 };
    const gps = [reference, { ...gpsAt(40, 0, reference), longitude: -179.9997402718545 }];
    const alignment = value(
      alignArToGps(
        [
          { x: 0, z: 0 },
          { x: 40, z: 0 },
        ],
        gps,
      ),
    );
    expect(value(applyAlignment({ x: 40, z: 0 }, alignment)).longitude).toBeCloseTo(
      gps[1].longitude,
      7,
    );
  });

  it('rejects missing, mismatched, repeated and nonfinite anchors', () => {
    error(alignArToGps([], []), 'INVALID_ALIGNMENT');
    error(alignArToGps(anchors, rotatedGps.slice(1)), 'INVALID_ALIGNMENT');
    error(alignArToGps([anchors[0], anchors[0]], rotatedGps.slice(0, 2)), 'INVALID_ALIGNMENT');
    error(alignArToGps(anchors.slice(0, 2), [origin, origin]), 'INVALID_ALIGNMENT');
    error(
      alignArToGps([{ x: NaN, z: 0 }, anchors[1]], rotatedGps.slice(0, 2)),
      'INVALID_COORDINATE',
    );
    error(
      alignArToGps(
        anchors,
        rotatedGps.map((point) => ({ ...point, accuracyMetres: 21 })),
      ),
      'POOR_GPS_ACCURACY',
    );
    error(
      alignArToGps(
        anchors,
        rotatedGps.map((point) => ({ ...point, latitude: 100 })),
      ),
      'INVALID_COORDINATE',
    );
    error(
      alignArToGps(anchors.slice(0, 2), [
        { latitude: 90, longitude: 0 },
        { latitude: 89, longitude: 0 },
      ]),
      'INVALID_ALIGNMENT',
    );
    error(
      alignArToGps(
        [
          { x: 1e200, z: 0 },
          { x: -1e200, z: 0 },
        ],
        rotatedGps.slice(0, 2),
      ),
      'INVALID_ALIGNMENT',
    );
  });

  it('validates caller-supplied alignment and transformed coordinates', () => {
    const alignment: Alignment = {
      origin,
      rotationRadians: 0,
      offset: { x: 0, z: 0 },
      fitErrorMetres: 0,
    };
    error(applyAlignment({ x: NaN, z: 0 }, alignment), 'INVALID_COORDINATE');
    error(
      applyAlignment(anchors[0], { ...alignment, origin: { latitude: 100, longitude: 0 } }),
      'INVALID_COORDINATE',
    );
    for (const changed of [
      { rotationRadians: NaN },
      { offset: { x: Infinity, z: 0 } },
      { offset: { x: 0, z: NaN } },
      { fitErrorMetres: NaN },
      { fitErrorMetres: -1 },
      { origin: { latitude: -90, longitude: 0 } },
    ]) {
      error(applyAlignment(anchors[0], { ...alignment, ...changed }), 'INVALID_ALIGNMENT');
    }
    error(applyAlignment({ x: 0, z: 1e20 }, alignment), 'INVALID_COORDINATE');
  });
});
