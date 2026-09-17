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
  type GpsPoint,
  type Result,
} from '../src/index';
import { gpsSquare, square20m } from './fixtures/synthetic-walks';

// Simulate untyped device/JSON input without weakening the public TypeScript API.
const malformedPoints = [
  { label: 'null', point: null },
  { label: 'undefined', point: undefined },
  { label: 'number', point: 0 },
  { label: 'string', point: 'point' },
  { label: 'boolean', point: false },
  { label: 'symbol', point: Symbol('point') },
  { label: 'bigint', point: 0n },
  { label: 'function', point: () => undefined },
  { label: 'array', point: [] },
  {
    label: 'array with coordinates',
    point: Object.assign([], { x: 0, z: 0, latitude: 0, longitude: 0 }),
  },
  { label: 'missing fields', point: {} },
  { label: 'partial fields', point: { x: 0, latitude: 0 } },
  { label: 'first numeric string', point: { x: '0', z: 0, latitude: '0', longitude: 0 } },
  { label: 'second numeric string', point: { x: 0, z: '0', latitude: 0, longitude: '0' } },
  { label: 'null field', point: { x: null, z: 0, latitude: null, longitude: 0 } },
  { label: 'nested field', point: { x: {}, z: 0, latitude: {}, longitude: 0 } },
];

const alignment: Alignment = {
  origin: gpsSquare[0],
  rotationRadians: 0,
  offset: { x: 0, z: 0 },
  fitErrorMetres: 0,
};

const malformedAlignments = [
  ...malformedPoints.map(({ label, point }) => ({ label, candidate: point })),
  { label: 'array with alignment fields', candidate: Object.assign([], alignment) },
  {
    label: 'function with alignment fields',
    candidate: Object.assign(() => undefined, alignment),
  },
  {
    label: 'missing origin',
    candidate: { rotationRadians: 0, offset: alignment.offset, fitErrorMetres: 0 },
  },
  {
    label: 'missing rotation',
    candidate: { origin: alignment.origin, offset: alignment.offset, fitErrorMetres: 0 },
  },
  {
    label: 'missing offset',
    candidate: { origin: alignment.origin, rotationRadians: 0, fitErrorMetres: 0 },
  },
  {
    label: 'missing fit error',
    candidate: { origin: alignment.origin, rotationRadians: 0, offset: alignment.offset },
  },
];

function invalidCoordinate(result: Result<unknown>): void {
  expect(result.ok).toBe(false);
  if (!result.ok) expect(result.error.code).toBe('INVALID_COORDINATE');
}

function checkArPoints(points: ArPoint[]): void {
  invalidCoordinate(closeShape(points));
  invalidCoordinate(planarArea(points));
  invalidCoordinate(detectCorners(points));
  invalidCoordinate(smoothShape(points));
  invalidCoordinate(alignArToGps(points, gpsSquare));
}

function checkGpsPoints(points: GpsPoint[]): void {
  invalidCoordinate(closeGpsShape(points));
  invalidCoordinate(geodesicArea(points));
  invalidCoordinate(alignArToGps(square20m, points));
}

describe('runtime point validation', () => {
  it.each(malformedPoints)('returns typed AR errors for $label', ({ point }) => {
    const bad = point as unknown as ArPoint;
    for (const index of [0, 1, 3]) {
      const points = [...square20m];
      points[index] = bad;
      checkArPoints(points);
    }
    invalidCoordinate(applyAlignment(bad, alignment));
    const badOffset = applyAlignment(square20m[0], { ...alignment, offset: bad });
    expect(badOffset.ok).toBe(false);
    if (!badOffset.ok) expect(badOffset.error.code).toBe('INVALID_ALIGNMENT');
  });

  it.each(malformedPoints)('returns typed GPS errors for $label', ({ point }) => {
    const bad = point as unknown as GpsPoint;
    for (const index of [0, 1, 3]) {
      const points = [...gpsSquare];
      points[index] = bad;
      checkGpsPoints(points);
    }
    invalidCoordinate(applyAlignment(square20m[0], { ...alignment, origin: bad }));
  });

  it('rejects holes in AR walks and anchors instead of skipping validation', () => {
    const points = Array<ArPoint>(4);
    points[0] = square20m[0];
    points[2] = square20m[2];
    points[3] = square20m[3];
    checkArPoints(points);
  });

  it('rejects holes in GPS walks and anchors', () => {
    const points = Array<GpsPoint>(4);
    points[0] = gpsSquare[0];
    points[2] = gpsSquare[2];
    points[3] = gpsSquare[3];
    checkGpsPoints(points);
  });
});

describe('runtime alignment validation', () => {
  it.each(malformedAlignments)('returns a typed alignment error for $label', ({ candidate }) => {
    const result = applyAlignment(square20m[0], candidate as unknown as Alignment);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe('INVALID_ALIGNMENT');
  });
});
