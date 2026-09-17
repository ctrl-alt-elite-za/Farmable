import { area as turfArea } from '@turf/area';

/** AR x is right/east, z is forward/north, in metres. Height is deliberately ignored. */
export interface ArPoint {
  readonly x: number;
  readonly z: number;
  readonly y?: number;
}

/** WGS84 degrees. Pass sensor accuracy when available; values over 20 m are rejected. */
export interface GpsPoint {
  readonly latitude: number;
  readonly longitude: number;
  readonly accuracyMetres?: number;
}

export type GeometryErrorCode =
  | 'TOO_FEW_POINTS'
  | 'INVALID_COORDINATE'
  | 'POOR_GPS_ACCURACY'
  | 'SELF_INTERSECTION'
  | 'DEGENERATE_SHAPE'
  | 'INVALID_OPTIONS'
  | 'INVALID_ALIGNMENT';

export interface GeometryError {
  readonly code: GeometryErrorCode;
  readonly message: string;
}

export type Result<T> =
  { readonly ok: true; readonly value: T } | { readonly ok: false; readonly error: GeometryError };

const EPSILON = 1e-8;
const RADIANS = Math.PI / 180;
// The same mean Earth radius as Turf. Local projections are for farm-scale walks.
const EARTH_RADIUS = 6371008.8;

function fail(code: GeometryErrorCode, message: string): Result<never> {
  return { ok: false, error: { code, message } };
}

function same(a: ArPoint, b: ArPoint): boolean {
  return Math.hypot(a.x - b.x, a.z - b.z) <= EPSILON;
}

function validAr(point: ArPoint): boolean {
  return Number.isFinite(point.x) && Number.isFinite(point.z);
}

function gpsError(point: GpsPoint): GeometryError | undefined {
  if (
    !Number.isFinite(point.latitude) ||
    !Number.isFinite(point.longitude) ||
    Math.abs(point.latitude) > 90 ||
    Math.abs(point.longitude) > 180
  ) {
    return { code: 'INVALID_COORDINATE', message: 'GPS coordinates must be valid WGS84 degrees.' };
  }
  if (point.accuracyMetres !== undefined) {
    if (!Number.isFinite(point.accuracyMetres) || point.accuracyMetres < 0) {
      return {
        code: 'INVALID_COORDINATE',
        message: 'GPS accuracy must be finite and nonnegative.',
      };
    }
    if (point.accuracyMetres > 20) {
      return { code: 'POOR_GPS_ACCURACY', message: 'GPS accuracy is worse than 20 metres.' };
    }
  }
}

function cross(a: ArPoint, b: ArPoint, c: ArPoint): number {
  return (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x);
}

function onSegment(a: ArPoint, b: ArPoint, p: ArPoint): boolean {
  return (
    Math.abs(cross(a, b, p)) <= EPSILON &&
    p.x >= Math.min(a.x, b.x) - EPSILON &&
    p.x <= Math.max(a.x, b.x) + EPSILON &&
    p.z >= Math.min(a.z, b.z) - EPSILON &&
    p.z <= Math.max(a.z, b.z) + EPSILON
  );
}

function intersects(a: ArPoint, b: ArPoint, c: ArPoint, d: ArPoint): boolean {
  const abC = cross(a, b, c);
  const abD = cross(a, b, d);
  const cdA = cross(c, d, a);
  const cdB = cross(c, d, b);
  return (
    (((abC > EPSILON && abD < -EPSILON) || (abC < -EPSILON && abD > EPSILON)) &&
      ((cdA > EPSILON && cdB < -EPSILON) || (cdA < -EPSILON && cdB > EPSILON))) ||
    onSegment(a, b, c) ||
    onSegment(a, b, d) ||
    onSegment(c, d, a) ||
    onSegment(c, d, b)
  );
}

function signedArea(points: readonly ArPoint[]): number {
  // Translate to the first point to avoid cancellation at large world offsets.
  const origin = points[0];
  let sum = 0;
  for (let i = 1; i < points.length - 1; i++) {
    sum += cross(origin, points[i], points[i + 1]);
  }
  return sum / 2;
}

function ring<T>(points: readonly T[], projected: readonly ArPoint[]): Result<T[]> {
  if (projected.some((point) => !validAr(point))) {
    return fail('INVALID_COORDINATE', 'Coordinates must be finite.');
  }
  const indices: number[] = [];
  for (let i = 0; i < points.length; i++) {
    if (!indices.length || !same(projected[i], projected[indices[indices.length - 1]])) {
      indices.push(i);
    }
  }
  while (
    indices.length > 1 &&
    same(projected[indices[0]], projected[indices[indices.length - 1]])
  ) {
    indices.pop();
  }
  if (indices.length < 3) {
    return fail('TOO_FEW_POINTS', 'A shape needs at least three distinct points.');
  }
  const flat = indices.map((index) => projected[index]);
  for (let i = 0; i < flat.length; i++) {
    const previous = flat[(i + flat.length - 1) % flat.length];
    const current = flat[i];
    const next = flat[(i + 1) % flat.length];
    if (
      Math.abs(cross(previous, current, next)) <= EPSILON &&
      (current.x - previous.x) * (next.x - current.x) +
        (current.z - previous.z) * (next.z - current.z) <
        -EPSILON
    ) {
      return fail('SELF_INTERSECTION', 'Adjacent edges overlap or double back.');
    }
    for (let j = i + 1; j < flat.length; j++) {
      if (j === i + 1 || (i === 0 && j === flat.length - 1)) continue;
      if (intersects(current, next, flat[j], flat[(j + 1) % flat.length])) {
        return fail('SELF_INTERSECTION', 'The shape crosses or touches itself.');
      }
    }
  }
  const area = Math.abs(signedArea(flat));
  if (!Number.isFinite(area) || area <= EPSILON) {
    return fail('DEGENERATE_SHAPE', 'The shape must enclose a finite, nonzero area.');
  }
  const clean = indices.map((index) => points[index]);
  return { ok: true, value: [...clean, clean[0]] };
}

/** Removes consecutive/closing duplicates, validates topology, and returns a closed ring. */
export function closeShape(points: readonly ArPoint[]): Result<ArPoint[]> {
  return ring(points, points);
}

export function planarArea(points: readonly ArPoint[]): Result<number> {
  const shape = closeShape(points);
  return shape.ok ? { ok: true, value: Math.abs(signedArea(shape.value)) } : shape;
}

function longitudeDelta(longitude: number, origin: number): number {
  return ((longitude - origin + 540) % 360) - 180;
}

function project(point: GpsPoint, origin: GpsPoint): ArPoint {
  return {
    x:
      longitudeDelta(point.longitude, origin.longitude) *
      RADIANS *
      EARTH_RADIUS *
      Math.cos(origin.latitude * RADIANS),
    z: (point.latitude - origin.latitude) * RADIANS * EARTH_RADIUS,
  };
}

export function closeGpsShape(points: readonly GpsPoint[]): Result<GpsPoint[]> {
  for (const point of points) {
    const error = gpsError(point);
    if (error) return { ok: false, error };
  }
  return ring(
    points,
    points.map((point) => project(point, points[0])),
  );
}

/** Geodesic square metres via Turf's spherical model, accepting WGS84 lat/lon. */
export function geodesicArea(points: readonly GpsPoint[]): Result<number> {
  const shape = closeGpsShape(points);
  if (!shape.ok) return shape;
  const origin = shape.value[0].longitude;
  // Unwrap the dateline so a small field crossing 180° is not treated as globe-sized.
  const coordinates = shape.value.map((point) => [
    origin + longitudeDelta(point.longitude, origin),
    point.latitude,
  ]);
  const area = turfArea({ type: 'Polygon', coordinates: [coordinates] });
  return Number.isFinite(area) && area > EPSILON
    ? { ok: true, value: area }
    : fail('DEGENERATE_SHAPE', 'The GPS shape must enclose a finite, nonzero area.');
}

export interface Corner {
  readonly index: number;
  readonly point: ArPoint;
  readonly turnDegrees: number;
}

function turnDegrees(previous: ArPoint, current: ArPoint, next: ArPoint): number {
  const dot =
    (current.x - previous.x) * (next.x - current.x) +
    (current.z - previous.z) * (next.z - current.z);
  return Math.abs(Math.atan2(cross(previous, current, next), dot)) / RADIANS;
}

/** Indices refer to the cleaned, open ring (the repeated closing point is omitted). */
export function detectCorners(points: readonly ArPoint[], minTurnDegrees = 45): Result<Corner[]> {
  if (!Number.isFinite(minTurnDegrees) || minTurnDegrees < 0 || minTurnDegrees > 180) {
    return fail('INVALID_OPTIONS', 'Corner threshold must be between 0 and 180 degrees.');
  }
  const shape = closeShape(points);
  if (!shape.ok) return shape;
  const open = shape.value.slice(0, -1);
  const corners = open.flatMap((point, index) => {
    const angle = turnDegrees(
      open[(index + open.length - 1) % open.length],
      point,
      open[(index + 1) % open.length],
    );
    return angle >= minTurnDegrees ? [{ index, point, turnDegrees: angle }] : [];
  });
  return { ok: true, value: corners };
}

export interface SmoothingOptions {
  readonly strength?: number;
  readonly iterations?: number;
  readonly cornerThresholdDegrees?: number;
}

/** Cyclic neighbor averaging in metres; protect sharp corners and revalidate every pass. */
export function smoothShape(
  points: readonly ArPoint[],
  options: SmoothingOptions = {},
): Result<ArPoint[]> {
  const { strength = 0.25, iterations = 1, cornerThresholdDegrees = 45 } = options;
  if (
    !Number.isFinite(strength) ||
    strength < 0 ||
    strength > 1 ||
    !Number.isInteger(iterations) ||
    iterations < 0 ||
    iterations > 100 ||
    !Number.isFinite(cornerThresholdDegrees) ||
    cornerThresholdDegrees < 0 ||
    cornerThresholdDegrees > 180
  ) {
    return fail(
      'INVALID_OPTIONS',
      'Use strength 0–1, iterations 0–100, and corner threshold 0–180.',
    );
  }
  let shape = closeShape(points);
  for (let pass = 0; pass < iterations && shape.ok; pass++) {
    const open: ArPoint[] = shape.value.slice(0, -1);
    const smoothed = open.map((point, index) => {
      const previous = open[(index + open.length - 1) % open.length];
      const next = open[(index + 1) % open.length];
      if (turnDegrees(previous, point, next) >= cornerThresholdDegrees) return point;
      return {
        ...point,
        x: point.x * (1 - strength) + ((previous.x + next.x) * strength) / 2,
        z: point.z * (1 - strength) + ((previous.z + next.z) * strength) / 2,
      };
    });
    shape = closeShape(smoothed);
  }
  return shape;
}

export interface Alignment {
  readonly origin: GpsPoint;
  /** Positive rotation turns AR right toward geographic north. */
  readonly rotationRadians: number;
  /** East/north metres relative to origin; applied after rotation. */
  readonly offset: ArPoint;
  /** RMS Euclidean residual across paired anchors, in metres. No scale is fitted. */
  readonly fitErrorMetres: number;
}

function rotate(point: ArPoint, angle: number): ArPoint {
  const cosine = Math.cos(angle);
  const sine = Math.sin(angle);
  return { x: point.x * cosine - point.z * sine, z: point.x * sine + point.z * cosine };
}

function centroid(points: readonly ArPoint[]): ArPoint {
  return {
    x: points.reduce((sum, point) => sum + point.x, 0) / points.length,
    z: points.reduce((sum, point) => sum + point.z, 0) / points.length,
  };
}

/** Least-squares rigid alignment of corresponding anchors; at least two distinct pairs. */
export function alignArToGps(ar: readonly ArPoint[], gps: readonly GpsPoint[]): Result<Alignment> {
  if (ar.length < 2 || ar.length !== gps.length) {
    return fail('INVALID_ALIGNMENT', 'Supply at least two corresponding AR/GPS anchors.');
  }
  if (ar.some((point) => !validAr(point))) {
    return fail('INVALID_COORDINATE', 'AR anchors must be finite.');
  }
  for (const point of gps) {
    const error = gpsError(point);
    if (error) return { ok: false, error };
  }
  const origin = { ...gps[0] };
  if (Math.abs(Math.cos(origin.latitude * RADIANS)) <= EPSILON) {
    return fail('INVALID_ALIGNMENT', 'A local east/north projection is undefined at the poles.');
  }
  const targets = gps.map((point) => project(point, origin));
  const sourceCentre = centroid(ar);
  const targetCentre = centroid(targets);
  let dot = 0;
  let determinant = 0;
  for (let i = 0; i < ar.length; i++) {
    const x = ar[i].x - sourceCentre.x;
    const z = ar[i].z - sourceCentre.z;
    const east = targets[i].x - targetCentre.x;
    const north = targets[i].z - targetCentre.z;
    dot += x * east + z * north;
    determinant += x * north - z * east;
  }
  if (
    !Number.isFinite(dot) ||
    !Number.isFinite(determinant) ||
    Math.hypot(dot, determinant) <= EPSILON
  ) {
    return fail('INVALID_ALIGNMENT', 'Anchors do not determine a finite rotation.');
  }
  const rotationRadians = Math.atan2(determinant, dot);
  const centre = rotate(sourceCentre, rotationRadians);
  const offset = { x: targetCentre.x - centre.x, z: targetCentre.z - centre.z };
  const residuals = ar.map((point, index) => {
    const rotated = rotate(point, rotationRadians);
    return (
      (rotated.x + offset.x - targets[index].x) ** 2 +
      (rotated.z + offset.z - targets[index].z) ** 2
    );
  });
  const fitErrorMetres = Math.sqrt(residuals.reduce((sum, value) => sum + value, 0) / ar.length);
  if (!Number.isFinite(fitErrorMetres) || !validAr(offset)) {
    return fail('INVALID_ALIGNMENT', 'Alignment exceeded finite coordinate limits.');
  }
  return { ok: true, value: { origin, rotationRadians, offset, fitErrorMetres } };
}

export function applyAlignment(point: ArPoint, alignment: Alignment): Result<GpsPoint> {
  if (!validAr(point)) return fail('INVALID_COORDINATE', 'AR coordinates must be finite.');
  const error = gpsError(alignment.origin);
  if (error) return { ok: false, error };
  if (
    !Number.isFinite(alignment.rotationRadians) ||
    !validAr(alignment.offset) ||
    !Number.isFinite(alignment.fitErrorMetres) ||
    alignment.fitErrorMetres < 0 ||
    Math.abs(Math.cos(alignment.origin.latitude * RADIANS)) <= EPSILON
  ) {
    return fail('INVALID_ALIGNMENT', 'Alignment must contain finite values and a nonpolar origin.');
  }
  const rotated = rotate(point, alignment.rotationRadians);
  const latitude =
    alignment.origin.latitude + (rotated.z + alignment.offset.z) / EARTH_RADIUS / RADIANS;
  const longitude =
    alignment.origin.longitude +
    (rotated.x + alignment.offset.x) /
      (EARTH_RADIUS * Math.cos(alignment.origin.latitude * RADIANS)) /
      RADIANS;
  const result = { latitude, longitude: ((((longitude + 180) % 360) + 360) % 360) - 180 };
  const outputError = gpsError(result);
  return outputError ? { ok: false, error: outputError } : { ok: true, value: result };
}
